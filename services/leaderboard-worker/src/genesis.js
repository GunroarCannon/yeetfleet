// The Seeker Genesis Token: a Token-2022 NFT whose mint is a member of the
// Seeker group (tokenGroupMember.group == GENESIS_GROUP). Only the group's
// authority can add members, so the extension can't be forged. It lives on
// mainnet; a pilot's address is the same on every cluster, so devnet builds
// check mainnet too.

export const TOKEN_2022 = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb";

// A slow RPC must not hold a sign-in past the game's own request timeout.
const RPC_TIMEOUT_MS = 6000;

/**
 * A JSON-RPC call; throws on a transport or RPC error, or after
 * [RPC_TIMEOUT_MS].
 * @param {string} url
 * @param {string} method
 * @param {any[]} params
 * @param {typeof fetch} fetchFn
 */
export async function rpc(url, method, params, fetchFn = fetch) {
  const res = await fetchFn(url, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
    signal: AbortSignal.timeout(RPC_TIMEOUT_MS),
  });
  if (!res.ok) throw new Error(`${method}: HTTP ${res.status}`);
  const body = await res.json();
  if (body.error) throw new Error(`${method}: ${body.error.message}`);
  return body.result;
}

/**
 * The Genesis Token mint [owner] holds, or null. Throws when the RPC can't
 * be reached (the caller decides what that means).
 * @param {string} owner
 * @param {{rpcUrl: string, group: string, fetchFn?: typeof fetch}} opts
 */
export async function genesisMint(owner, { rpcUrl, group, fetchFn = fetch }) {
  const accounts = await rpc(rpcUrl, "getTokenAccountsByOwner",
    [owner, { programId: TOKEN_2022 }, { encoding: "jsonParsed", commitment: "confirmed" }], fetchFn);
  // NFTs only: one token, no decimals. Zero-balance accounts are skipped.
  const mints = (accounts?.value ?? [])
    .map((a) => a.account?.data?.parsed?.info)
    .filter((i) => i && i.tokenAmount?.amount === "1" && i.tokenAmount?.decimals === 0)
    .map((i) => i.mint);
  for (let i = 0; i < mints.length; i += 100) {
    const batch = mints.slice(i, i + 100);
    const infos = await rpc(rpcUrl, "getMultipleAccounts", [batch, { encoding: "jsonParsed" }], fetchFn);
    for (const [k, acc] of (infos?.value ?? []).entries()) {
      if (acc?.owner !== TOKEN_2022) continue;
      const exts = acc.data?.parsed?.info?.extensions ?? [];
      if (exts.some((e) => e.extension === "tokenGroupMember" && e.state?.group === group && e.state?.mint === batch[k])) {
        return batch[k];
      }
    }
  }
  return null;
}
