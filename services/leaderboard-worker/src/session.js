// Session tokens: "<payload>.<mac>", both base64url. The payload is the
// pilot ({pk, gm, exp}); the mac is HMAC-SHA256 under SESSION_SECRET. No
// table: a token is good until it expires or the secret is rotated.

const enc = new TextEncoder();

function b64url(bytes) {
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function unb64url(text) {
  const b64 = text.replace(/-/g, "+").replace(/_/g, "/");
  return Uint8Array.from(atob(b64 + "=".repeat((4 - (b64.length % 4)) % 4)), (c) => c.charCodeAt(0));
}

async function key(secret) {
  return crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

/**
 * @param {{pk: string, gm: string | null}} pilot public key, Genesis Token mint
 * @param {string} secret
 * @param {number} ttlSec
 * @param {number} now ms
 */
export async function issue(pilot, secret, ttlSec, now) {
  const payload = b64url(enc.encode(JSON.stringify({ pk: pilot.pk, gm: pilot.gm, exp: Math.floor(now / 1000) + ttlSec })));
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", await key(secret), enc.encode(payload)));
  return `${payload}.${b64url(mac)}`;
}

/**
 * The pilot in a valid, unexpired token, or null.
 * @returns {Promise<{pk: string, gm: string | null, exp: number} | null>}
 */
export async function read(token, secret, now) {
  if (typeof token !== "string" || !secret) return null;
  const [payload, mac, extra] = token.split(".");
  if (!payload || !mac || extra !== undefined) return null;
  try {
    const ok = await crypto.subtle.verify("HMAC", await key(secret), unb64url(mac), enc.encode(payload));
    if (!ok) return null;
    const p = JSON.parse(new TextDecoder().decode(unb64url(payload)));
    return p.exp * 1000 > now ? p : null;
  } catch {
    return null;
  }
}
