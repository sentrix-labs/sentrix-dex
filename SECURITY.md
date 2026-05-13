# Security policy

## Secrets

- **Never commit `.env` or any file containing a private key.** `.gitignore` blocks `.env*` patterns.
- The deployer key for Sentrix DEX contracts lives off-repo in operator-internal storage. Reference it via the `DEPLOYER_PRIVATE_KEY` env var only — never inline in scripts.
- If you suspect a leak, rotate the key immediately and notify `security@sentrixchain.com`.

## Vulnerability disclosure

Email **`security@sentrixchain.com`** with reproducer + impact assessment, or open a private GitHub Security Advisory at <https://github.com/sentrix-labs/sentrix-dex/security/advisories/new>. We respond within 72 hours.

Do not file public issues for security bugs.

## Immutability

Sentrix DEX is a UniswapV2 fork; deployed factory, pair, and router contracts are **immutable** — there is no upgrade proxy. Audit thoroughly before mainnet deploy. If a vulnerability is found post-deploy, the response is "deploy v2 + advise migration", not "patch in place."

## Common AMM threat classes

When reviewing this codebase, pay particular attention to:

- Reentrancy across swap / mint / burn paths
- Donation / first-deposit inflation attacks on empty pairs
- Oracle and price-manipulation surface when LP supply is small
- Slippage and `deadline` validation in the router
- Fee-on-transfer and rebasing token interactions
- Integer rounding in `getAmountOut` / `getAmountIn`

## Scope

In scope:

- All contracts in `contracts/`
- All deploy scripts in `script/`
- `foundry.toml` and CI workflow

Out of scope (covered elsewhere):

- Sentrix node / consensus (`sentrix-labs/sentrix`)
- Canonical contracts — WSRX, Multicall3 (`sentrix-labs/canonical-contracts`)
- Frontend / DEX UI (`SentrisCloud/frontend`)
