# Solana wallets and mints for Yeetfleet

Public addresses only. **No secret key ever goes in this repo.**

| What | Address | Cluster | Secret key lives at |
|---|---|---|---|
| Treasury (receives SKR payments) | `2ZGn8kxkJae4Q4sjU2uZiXT5x5ZtzSQh2P1KASYTn4R1` | devnet and mainnet (same key) | `~/.config/solana/yeetfleet-treasury.json` on the dev PC |
| dSKR test mint (6 decimals, like SKR) | `J1zbnVh8XFzjiBgXayMMxbg46zxZ5DVm1e8YWhxue6bK` | devnet | mint authority: `~/.config/solana/id.json` (`4vqJJB8e…MghR`); mint keypair: `~/.config/solana/yeetfleet-dskr-mint.json` |
| SKR (the real token) | `SKRbvo6Gf7GondiT3BbTfuRDPqLWei4j2Qy2NPGZhW3` | mainnet | not ours |
| Test pilot (Phantom on the emulator) | `GE7bEoKnVEkPQ7U7sQswPqq2AbZfNWEgMxcQiYjyHLdK` | devnet; holds dSKR | in Phantom |

All created 2026-10-08. The game reads these from `Chain` (`modules/chain/scripts/chain.gd`).

## Treasury

- **Back up `yeetfleet-treasury.json` now** (a password manager or an offline
  copy). It is the only copy; lose it and every SKR paid in is gone. Before
  mainnet, consider moving the treasury to a hardware wallet or a multisig
  (Squads) and updating `Chain.TREASURY`.
- The treasury needs **no SOL**: the buyer's wallet pays the rent for its
  SKR token account on the first purchase. The Worker holds only its public
  address, never a key.
- Check it: `solana balance 2ZGn8kxkJae4Q4sjU2uZiXT5x5ZtzSQh2P1KASYTn4R1 --url devnet`,
  `spl-token accounts --owner 2ZGn8kxkJae4Q4sjU2uZiXT5x5ZtzSQh2P1KASYTn4R1 --url devnet`.
- Burning (the plan's burn share): the treasury burns it in batches, e.g.
  weekly: `spl-token burn <treasury SKR account> <amount> --owner ~/.config/solana/yeetfleet-treasury.json`.
  Payments themselves don't burn; that keeps each one a plain transfer the
  Worker can verify.

## dSKR

More test tokens for a pilot:
`spl-token mint J1zbnVh8XFzjiBgXayMMxbg46zxZ5DVm1e8YWhxue6bK 1000 --recipient-owner <pilot> --url devnet`
(create the pilot's account first if it has none:
`spl-token create-account J1zbnVh8XFzjiBgXayMMxbg46zxZ5DVm1e8YWhxue6bK --owner <pilot> --fee-payer ~/.config/solana/id.json --url devnet`).
