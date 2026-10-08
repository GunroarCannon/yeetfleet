// Sign-In-With-Solana: read the message a wallet signed, and check its
// Ed25519 signature. The layout is the standard's (the wallet writes it from
// the fields the game sent):
//
//   <domain> wants you to sign in with your Solana account:
//   <address>
//
//   <statement>
//
//   Nonce: <nonce>
//   Issued At: <iso time>
//   …

import { decode } from "./base58.js";

const HEADER = " wants you to sign in with your Solana account:";
const FIELDS = {
  "URI": "uri",
  "Version": "version",
  "Chain ID": "chainId",
  "Nonce": "nonce",
  "Issued At": "issuedAt",
  "Expiration Time": "expirationTime",
  "Not Before": "notBefore",
  "Request ID": "requestId",
};

/**
 * The fields of a SIWS message, or null when it isn't one.
 * @param {string} text
 */
export function parse(text) {
  const lines = text.split("\n");
  if (lines.length < 2 || !lines[0].endsWith(HEADER)) return null;
  const out = { domain: lines[0].slice(0, -HEADER.length), address: lines[1], statement: "" };
  for (const line of lines.slice(2)) {
    const at = line.indexOf(": ");
    const key = at > 0 ? FIELDS[line.slice(0, at)] : undefined;
    if (key) {
      out[key] = line.slice(at + 2);
    } else if (line !== "" && !line.startsWith("- ") && line !== "Resources:" && out.statement === "") {
      out.statement = line;
    }
  }
  return out;
}

/**
 * True when [signature] is [address]'s Ed25519 signature of [message].
 * @param {string} address base58 public key
 * @param {Uint8Array} message
 * @param {Uint8Array} signature 64 bytes
 */
export async function verify(address, message, signature) {
  const key = decode(address);
  if (key === null || key.length !== 32 || signature.length !== 64) return false;
  try {
    const k = await crypto.subtle.importKey("raw", key, { name: "Ed25519" }, false, ["verify"]);
    return await crypto.subtle.verify({ name: "Ed25519" }, k, signature, message);
  } catch {
    return false;
  }
}

/** Standard base64 to bytes; null when it isn't base64. */
export function fromBase64(text) {
  try {
    return Uint8Array.from(atob(text), (c) => c.charCodeAt(0));
  } catch {
    return null;
  }
}
