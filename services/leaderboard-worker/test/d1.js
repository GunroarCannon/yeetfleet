// A stand-in for Cloudflare D1 over Node's built-in SQLite, enough of the
// API the Worker uses: prepare().bind().first() / all() / run(), batch().
// It runs the real schema.sql, so the tests exercise the real SQL.

import { DatabaseSync } from "node:sqlite";
import { readFileSync } from "node:fs";

const SCHEMA = new URL("../schema.sql", import.meta.url);

class Statement {
  constructor(db, sql, args = []) {
    this.db = db;
    this.sql = sql;
    this.args = args;
  }

  bind(...args) {
    return new Statement(this.db, this.sql, args);
  }

  async first(column) {
    const row = this.db.prepare(this.sql).get(...this.args);
    if (row === undefined) return null;
    return column ? row[column] : { ...row };
  }

  async all() {
    return { success: true, results: this.db.prepare(this.sql).all(...this.args).map((r) => ({ ...r })) };
  }

  async run() {
    const r = this.db.prepare(this.sql).run(...this.args);
    return { success: true, meta: { changes: Number(r.changes), last_row_id: Number(r.lastInsertRowid) } };
  }
}

export class FakeD1 {
  constructor() {
    this.db = new DatabaseSync(":memory:");
    this.db.exec(readFileSync(SCHEMA, "utf8"));
  }

  prepare(sql) {
    return new Statement(this.db, sql);
  }

  /** Like D1: all or nothing. */
  async batch(statements) {
    this.db.exec("BEGIN");
    try {
      const out = [];
      for (const s of statements) out.push(await s.run());
      this.db.exec("COMMIT");
      return out;
    } catch (e) {
      this.db.exec("ROLLBACK");
      throw e;
    }
  }
}
