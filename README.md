# Sentrix DEX

Native AMM for Sentrix Chain. UniswapV2-equivalent DEX targeting WSRX/stable pairs as
the canonical price-discovery layer for SRX.

> **Status (2026-04-30):** scaffold + deploy plan only. No contracts shipped yet.
> Mainnet deploy gated on dedicated fresh-brain implementation session + audit pass.

---

## Why this exists

SRX has no exchange price today. The cheapest path to real price discovery without
paying CEX listing fees + market-maker commitments is a native DEX:

1. Deploy AMM contracts on Sentrix mainnet (this repo)
2. Seed first pool from Eco Fund allocation (existing canonical wallet `0xeb70…f14`)
3. List pool on DEXScreener / GeckoTerminal (free, automatic indexing)
4. Use the resulting on-chain volume as proof for CG / CMC / CEX submissions

Without a DEX, every other path stalls because external listings ask "show me the
DEX volume."

---

## Architecture

Standard UniswapV2 fork, ported to Solidity 0.8.24:

| Contract | Role |
|---|---|
| `SentrixV2Factory` | Creates pairs via CREATE2; admin owns the protocol-fee toggle |
| `SentrixV2Pair` | The AMM pool itself (mint, burn, swap, skim, sync) |
| `SentrixV2ERC20` | LP token base (EIP-2612 permit included) |
| `SentrixV2Router02` | High-level user-facing entry point — addLiquidity / swap / removeLiquidity |
| `SentrixV2Library` | Pure helpers: `quote`, `getAmountOut`, `getAmountIn`, `pairFor` |

Native SRX wrapping uses the existing canonical `WSRX` contract — see
`sentrix-labs/canonical-contracts` for the deployed address. Router accepts native
SRX via `swapExactSRXForTokens` etc. and wraps internally.

### Deviations from canonical UniV2

- Solidity 0.8.24 (vs. 0.5.16) — overflow checks become free; `unchecked` blocks used
  in the AMM math where the original explicitly asserts no overflow.
- `INIT_CODE_HASH` recomputed for our compiled `SentrixV2Pair` bytecode and embedded
  in `SentrixV2Library.pairFor` — must match the deployed factory's actual creation
  hash exactly.
- 0.30% LP fee retained (UniV2 default). Protocol-fee switch off at launch; can be
  enabled later via `setFeeTo()` to route 1/6 of LP fee to a treasury.

---

## Deploy plan (gated, NOT executed yet)

### Phase 1 — testnet bake (1-2 days)

1. Compile + run forge tests
2. Deploy to Sentrix testnet (chain 7120)
3. Seed test pool with WSRX-test + mock-stable
4. Verify swap / mint / burn paths
5. Verify on `verify.sentrixchain.com` Sourcify

### Phase 2 — mainnet deploy

1. Deploy `SentrixV2Factory` (admin = SentrixSafe `0xa252…`)
2. Compute INIT_CODE_HASH from compiled `Pair` bytecode
3. Patch hash into `SentrixV2Library.pairFor()` constant
4. Deploy `SentrixV2Router02` with (factory, WSRX) constructor args
5. Verify both contracts on Sourcify
6. Update `canonical-contracts/docs/addresses.md` with the deployed addresses
7. Pin a release tag (`sentrix-dex@v1.0.0`)

### Phase 3 — first pool + price seed

Operator decision (NOT scheduled yet):

- **Pair choice:** WSRX / stablecoin. Stablecoin candidates (in order of complexity):
  1. **Treasury-issued sIDR or sUSD** — simplest, founder backstop with off-chain
     reserve. Legal grey but pragmatic for early traction.
  2. **Bridged USDC** via LayerZero / Stargate — needs LZ endpoint deployed on
     Sentrix first. Multi-week scope.
  3. **Wrapped community stable** via partner — depends on partnership existing.

- **Initial price:** founder + treasury allocation decision. E.g., 500K SRX +
  $5K-equivalent stable → 1 SRX = $0.01.

- **Seed source:** Eco Fund (`0xeb70…f14`, 21M SRX premine) — within mandate.

---

## Pre-launch checklist

- [ ] Contracts implemented + tested (this is the next session's work)
- [ ] forge test coverage > 95% on Pair / Router math paths
- [ ] Slither / Mythril / Aderyn static analysis pass
- [ ] External audit (or peer review) of any deviation from canonical UniV2
- [ ] Testnet bake ≥ 24h with synthetic swap traffic
- [ ] Mainnet deploy from VPS4 with multisig admin (SentrixSafe)
- [ ] Sourcify verification of all deployed contracts
- [ ] Frontend integrated into `scan.sentrixchain.com` swap tab
  (existing scan UI needs a new `/swap` route — separate scope)
- [ ] DEXScreener + GeckoTerminal pool submission

---

## Local development

```bash
forge build --sizes
forge test -vvv

# Deploy
forge script script/Deploy.s.sol --rpc-url sentrix_testnet --broadcast
forge script script/Deploy.s.sol --rpc-url sentrix_mainnet --broadcast
```

---

## Roadmap (post-launch)

Phase 4 (V3 / concentrated liquidity), router aggregator, governance module, etc.
not in scope for v1.

---

## License

MIT (UniswapV2 derivative — original copyright preserved in headers).
