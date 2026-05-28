# Sentrix DEX

[![CI](https://github.com/sentrix-labs/sentrix-dex/actions/workflows/test.yml/badge.svg)](https://github.com/sentrix-labs/sentrix-dex/actions/workflows/test.yml)
[![License](https://img.shields.io/github/license/sentrix-labs/sentrix-dex)](LICENSE)
[![Latest release](https://img.shields.io/github/v/release/sentrix-labs/sentrix-dex?include_prereleases&sort=semver)](https://github.com/sentrix-labs/sentrix-dex/releases/latest)


Native AMM for Sentrix Chain. UniswapV2-equivalent DEX targeting WSRX/stable pairs as the canonical price-discovery layer for SRX.

> **Status:** **LIVE on mainnet + testnet** since 2026-05-07. Factory + Router02 deployed both chains; first WSRX/SGC pool seeded on mainnet. Live UI: [dex.sentrixchain.com](https://dex.sentrixchain.com) — swap, /pools, /add, /remove, /positions surfaces. Internal audit pass shipped 2026-05-07 (1 HIGH `feeToSetter` two-step rotation patched in source for v2 redeploys; deployed factory unaffected). See [`docs/ADDRESSES.md`](docs/ADDRESSES.md) for canonical addresses + INIT_CODE_HASH.

---

## Why this exists

SRX is not listed on any centralised exchange yet — there is no CEX
order book or market-maker commitment behind it. Price discovery so
far happens entirely on-chain through the AMM pools deployed here.
The cheapest path to broader external recognition (DEXScreener, CG,
CMC, eventual CEX listings) is to seed liquidity natively and let the
on-chain volume speak for itself.

1. Deploy AMM contracts on Sentrix mainnet ✅
2. Seed first pool from Eco Fund allocation ✅ (WSRX / SGC live on mainnet — small initial depth, see [`scan.sentrixchain.com`](https://scan.sentrixchain.com) for current liquidity + 24 h volume)
3. List pool on DEXScreener / GeckoTerminal (free, automatic indexing) — pending submission
4. Use the resulting on-chain volume as proof for CG / CMC / CEX submissions

> [!NOTE]
> Initial pool depth is small by design — the Eco Fund seeded a
> minimum-viable amount, not market-making liquidity. Quoted prices
> from a thin pool can swing sharply on small trades; check the live
> pool state on the explorer before sizing any execution.

---

## Architecture

Standard UniswapV2 fork, ported to Solidity 0.8.24:

| Contract | Role |
|---|---|
| [`SentrixV2Factory`](contracts/SentrixV2Factory.sol) | Creates pairs via CREATE2; admin owns the protocol-fee toggle |
| [`SentrixV2Pair`](contracts/SentrixV2Pair.sol) | The AMM pool itself (mint, burn, swap, skim, sync) |
| [`SentrixV2ERC20`](contracts/SentrixV2ERC20.sol) | LP token base (EIP-2612 permit included) |
| [`SentrixV2Router02`](contracts/SentrixV2Router02.sol) | High-level user-facing entry point — addLiquidity / swap / removeLiquidity |
| [`SentrixV2Library`](contracts/libraries/SentrixV2Library.sol) | Pure helpers: `quote`, `getAmountOut`, `getAmountIn`, `pairFor` |

Native SRX wrapping uses the existing canonical `WSRX` contract — see [`sentrix-labs/canonical-contracts`](https://github.com/sentrix-labs/canonical-contracts) for the deployed address. Router accepts native SRX via `swapExactSRXForTokens` etc. and wraps internally.

### Deviations from canonical UniV2

- Solidity 0.8.24 (vs. 0.5.16) — overflow checks become free; `unchecked` blocks used in the AMM math where the original explicitly asserts no overflow.
- `INIT_CODE_HASH` recomputed for our compiled `SentrixV2Pair` bytecode and embedded in `SentrixV2Library.pairFor` — must match the deployed factory's actual creation hash exactly.
- 0.30% LP fee retained (UniV2 default). Protocol-fee switch off at launch; can be enabled later via `setFeeTo()` to route 1/6 of LP fee to a treasury.

---

## Deployed contracts

Per `deployments/{7119,7120}.json` — `SentrixV2Factory` + `SentrixV2Router02` both deployed on each chain. Pair addresses are CREATE2-derived per-asset-pair; query `SentrixV2Factory.getPair(tokenA, tokenB)` or compute via `SentrixV2Library.pairFor(factory, tokenA, tokenB)`.

Mainnet first pool: WSRX/SGC, seeded 2026-05-07 (100 WSRX + 1M SGC genesis price).

---

## Local development

```bash
forge build --sizes
forge test -vvv

# Re-deploy (e.g., to a fresh testnet rebuild)
forge script script/Deploy.s.sol --rpc-url sentrix_testnet --broadcast
```

---

## Roadmap

Post-launch direction (no committed timeline):

- Concentrated-liquidity (V3-style) pool flavor
- Router aggregator across multiple pools
- Governance module for protocol-fee parameter changes
- Listing on DEXScreener + GeckoTerminal once volume justifies submission

---

## License

MIT (UniswapV2 derivative — original copyright preserved in headers).
