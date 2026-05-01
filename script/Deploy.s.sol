// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SentrixV2Factory} from "../contracts/SentrixV2Factory.sol";
import {SentrixV2Router02} from "../contracts/SentrixV2Router02.sol";
import {SentrixV2Pair} from "../contracts/SentrixV2Pair.sol";
import {SentrixV2Library} from "../contracts/libraries/SentrixV2Library.sol";

// One-shot deploy: Factory + Router. INIT_CODE_HASH is computed from the
// SentrixV2Pair creationCode at compile time and stored as a constant in
// SentrixV2Library. The deploy script asserts both expressions match before
// any user-facing contract goes live — catches the case where Pair was edited
// but Library wasn't re-patched.
//
// Usage:
//   DEPLOYER_PRIVATE_KEY=0x... \
//   FEE_TO_SETTER=0xa252...  \
//   WSRX=0x...              \
//   forge script script/Deploy.s.sol --rpc-url sentrix_mainnet --broadcast
contract Deploy is Script {
    // Mirror of contracts/libraries/SentrixV2Library.sol#INIT_CODE_HASH. Must
    // match exactly. The pre-deploy assertion below verifies this constant
    // equals the compiled Pair bytecode hash, but we still need a value here
    // to compare *against* — and the same value to live in the Library so
    // pairFor() returns correct addresses post-deploy.
    bytes32 internal constant LIBRARY_INIT_CODE_HASH =
        0xf7d8b4d1ce6c92cb3ce6b366dfb5977578db74e308b88facd5966df9e2a029dd;

    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address feeToSetter = vm.envAddress("FEE_TO_SETTER");
        address wsrx = vm.envAddress("WSRX");

        // Compute the actual hash of the Pair contract this build will deploy.
        // If anything in SentrixV2Pair (or its dependency tree) changed since
        // the Library constant was last patched, this won't match.
        bytes32 actualPairHash = keccak256(type(SentrixV2Pair).creationCode);
        require(
            actualPairHash == LIBRARY_INIT_CODE_HASH,
            "Deploy: Pair creationCode hash != LIBRARY_INIT_CODE_HASH. Repatch SentrixV2Library + this script."
        );

        vm.startBroadcast(deployerKey);

        SentrixV2Factory factory = new SentrixV2Factory(feeToSetter);
        console.log("SentrixV2Factory deployed at:", address(factory));

        // Belt-and-suspenders: re-read from the deployed Factory itself in case
        // the broadcasted bytecode somehow differs from the local artifact.
        bytes32 onChainHash = factory.pairCodeHash();
        require(onChainHash == LIBRARY_INIT_CODE_HASH, "Deploy: deployed Factory hash != Library constant");

        SentrixV2Router02 router = new SentrixV2Router02(address(factory), wsrx);
        console.log("SentrixV2Router02 deployed at:", address(router));
        console.log("Wired:");
        console.log("  factory      =", address(factory));
        console.log("  WSRX         =", wsrx);
        console.log("  feeToSetter  =", feeToSetter);
        console.log("  pairCodeHash =", uint256(onChainHash));

        console.log("");
        console.log("NEXT STEPS:");
        console.log(" 1. Verify both addresses on https://verify.sentrixchain.com");
        console.log(" 2. Update sentrix-labs/canonical-contracts/docs/addresses.md");
        console.log(" 3. Decide stablecoin pair + initial price ratio");
        console.log(" 4. Seed first pool from Eco Fund");

        vm.stopBroadcast();
    }
}
