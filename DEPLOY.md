# Sentrix DEX — deploy runbook

## Pre-flight

- Foundry installed (`forge --version`)
- Deployer wallet with ≥1 SRX for gas (mainnet) or testnet SRX from faucet
- Private key in env var (NEVER commit, use `! cat ~/path/key` flow)

## Mainnet deploy

```bash
cd ~/sentrix-dex

# 1. Verify INIT_CODE_HASH baked in matches compiled Pair
forge build --sizes
HASH_BAKED=$(grep "INIT_CODE_HASH =" contracts/libraries/SentrixV2Library.sol | grep -oE "0x[a-f0-9]+")
HASH_PAIR=$(cast keccak "$(jq -r '.bytecode.object' out/SentrixV2Pair.sol/SentrixV2Pair.json)")
[ "$HASH_BAKED" = "$HASH_PAIR" ] && echo "OK: hashes match" || echo "MISMATCH — re-patch Library + recompile"

# 2. Set deploy env (use ! prefix in shell or read from secure source)
export DEPLOYER_PRIVATE_KEY=0x...                                       # 1+ SRX for gas
export FEE_TO_SETTER=0xa25236925bc10954e0519731cc7ba97f4bb5714b         # SentrixSafe authority owner
export WSRX=0x4693b113e523A196d9579333c4ab8358e2656553                  # canonical mainnet WSRX

# 3. Dry run first (no broadcast)
forge script script/Deploy.s.sol --rpc-url sentrix_mainnet

# 4. Real deploy
forge script script/Deploy.s.sol --rpc-url sentrix_mainnet --broadcast --slow

# 5. Capture printed addresses, update docs
# Output will look like:
#   SentrixV2Factory deployed at: 0x...
#   SentrixV2Router02 deployed at: 0x...
```

## Verify on Sourcify

```bash
forge verify-contract \
  --verifier sourcify \
  --verifier-url https://verify.sentrixchain.com \
  --chain 7119 \
  $FACTORY_ADDR contracts/SentrixV2Factory.sol:SentrixV2Factory

forge verify-contract \
  --verifier sourcify \
  --verifier-url https://verify.sentrixchain.com \
  --chain 7119 \
  $ROUTER_ADDR contracts/SentrixV2Router02.sol:SentrixV2Router02
```

## Post-deploy: register addresses in canonical-contracts

```bash
cd ~/canonical-contracts
# Edit deployments/7119.json — append:
#   "SentrixV2Factory": { "address": "0x...", "deployedAt": "...", "tx": "0x..." },
#   "SentrixV2Router02": { ... }
# Then regenerate ADDRESSES.md:
./script/GenerateAddressDocs.sh
git add deployments/7119.json docs/ADDRESSES.md
git -c commit.gpgsign=false commit -m "addresses: register SentrixV2 DEX (Factory + Router02)"
```

## First pool seed (FOUNDER DECISION — separate manual step)

After Factory + Router live + verified:

1. Deploy a stablecoin SRC-20 (or use a wrapped/bridged stable — pricing strategy is operator-internal)
2. From the Eco Fund wallet (`0xeb70fdefd00fdb768dec06c478f450c351499f14`):
   - Approve Router for `X` SRX-equivalent of WSRX + `Y` of stable
   - Call `Router.addLiquiditySRX(stable, Y, Y_min, X_min, ecoFund, deadline)` with `value: X` SRX
3. The pool gets created automatically (Factory.createPair internally), and LP tokens are minted to ecoFund
4. Initial price = X / Y (in SRX-per-stable terms)

## Rollback

If a deploy goes wrong (wrong hash, wrong WSRX, etc.):
- Factory + Router are independent; redeploy the broken one
- Already-created pairs from a wrong Factory are orphaned but harmless (no liquidity, no LP holders)
- Update canonical-contracts/docs/ADDRESSES.md with the corrected addresses
