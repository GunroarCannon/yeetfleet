// The wallet's identity check: assetlinks.json at the Worker's origin.

import { test } from "node:test";
import assert from "node:assert/strict";
import { makeEnv } from "./helpers.js";
import worker from "../src/index.js";

test("assetlinks.json lists the APK, with a Content-Type of exactly application/json", async () => {
  const res = await worker.fetch(new Request("https://w.example/.well-known/assetlinks.json"), makeEnv());
  assert.equal(res.status, 200);
  // Phantom's verifier compares the header string for equality: no charset.
  assert.equal(res.headers.get("content-type"), "application/json");
  const [s] = await res.json();
  assert.deepEqual(s.relation, ["delegate_permission/common.handle_all_urls"]);
  assert.equal(s.target.namespace, "android_app");
  assert.equal(s.target.package_name, "com.critbox.yeetfleet");
  assert.ok(s.target.sha256_cert_fingerprints.length >= 2);
});
