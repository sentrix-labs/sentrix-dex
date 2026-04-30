// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SentrixV2Factory} from "../contracts/SentrixV2Factory.sol";

// Deploy script — Sentrix DEX v1.
//
// Usage:
//   DEPLOYER_PRIVATE_KEY=0x... forge script script/Deploy.s.sol \
//     --rpc-url sentrix_testnet --broadcast
//
// Notes:
//   - WSRX address is read from env (canonical-contracts deployment).
//     Mainnet: see sentrix-labs/canonical-contracts/docs/addresses.md
//   - Factory feeToSetter = SentrixSafe (multisig admin).
//     Mainnet: 0xa25236925bc1...  (from CLAUDE.md / project_brand_architecture)
//   - After Factory deploys, run a separate forge script to compute
//     the pair INIT_CODE_HASH, patch SentrixV2Library, recompile, then
//     deploy Router02. Two-step deploy is intentional — UniV2 design.
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address feeToSetter = vm.envAddress("FEE_TO_SETTER");

        vm.startBroadcast(deployerKey);

        SentrixV2Factory factory = new SentrixV2Factory(feeToSetter);
        console.log("SentrixV2Factory deployed at:", address(factory));
        console.log("feeToSetter:", feeToSetter);
        console.log("");
        console.log("NEXT STEPS:");
        console.log("1. Compute INIT_CODE_HASH from compiled SentrixV2Pair bytecode");
        console.log("2. Patch SentrixV2Library.pairFor() constant");
        console.log("3. Recompile, then deploy SentrixV2Router02");
        console.log("4. Verify both contracts on https://verify.sentrixchain.com");

        vm.stopBroadcast();
    }
}
