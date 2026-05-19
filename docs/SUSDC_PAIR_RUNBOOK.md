# SRX/sUSDC Pair Runbook

This runbook is for the DEX step after the official Base USDC -> Sentrix sUSDC Hyperlane Warp Route is deployed and verified.

## Preconditions

- sUSDC exists on Sentrix with name `Sentrix Bridged USDC`, symbol `sUSDC`, and `6` decimals.
- The bridge passed Base -> Sentrix and Sentrix -> Base tests.
- The bridge invariant holds: Sentrix sUSDC total supply is less than or equal to Base USDC locked collateral.
- sUSDC is listed in the Sentrix token list.
- The frontend DEX env var is set:
  - Testnet: `NEXT_PUBLIC_SUSDC_TESTNET_ADDRESS`
  - Mainnet: `NEXT_PUBLIC_SUSDC_MAINNET_ADDRESS`

## Pair Creation

The pair is created through normal UniswapV2 flow:

1. Approve sUSDC to `SentrixV2Router02`.
2. Call `addLiquiditySRX` with sUSDC as the token side, or `addLiquidity` with WSRX/sUSDC.
3. Record the pair from `SentrixV2Factory.getPair(WSRX, sUSDC)`.
4. Update `config/susdc-pair.json` with the sUSDC and pair addresses.

## Routing

Preferred SRX price route:

1. SRX/sUSDC
2. SRX/sUSDT when available

Do not mark SRX/sUSDC as primary until liquidity is deep enough for normal user trades and price impact checks are acceptable.

## Safety Checks

- sUSDC address is non-zero and checksummed.
- sUSDC decimals are `6`.
- Pair reserves are non-zero after seeding.
- LP tokens are held by the intended LP wallet or multisig.
- No DEX config points to a placeholder address.
- Explorer links resolve for sUSDC and the pair.
