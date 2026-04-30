// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {SentrixV2Factory} from "../contracts/SentrixV2Factory.sol";
import {SentrixV2Router02} from "../contracts/SentrixV2Router02.sol";
import {SentrixV2Library} from "../contracts/libraries/SentrixV2Library.sol";

// One-shot deploy: Factory + Router. INIT_CODE_HASH is already baked into
// SentrixV2Library at compile time (computed from SentrixV2Pair creationCode
// and patched offline before this script runs — see README + the bash one-
// liner that invokes `cast keccak` on Pair's bytecode).
//
// Usage:
//   DEPLOYER_PRIVATE_KEY=0x... \
//   FEE_TO_SETTER=0xa252...  \
//   WSRX=0x...              \
//   forge script script/Deploy.s.sol --rpc-url sentrix_mainnet --broadcast
contract Deploy is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("DEPLOYER_PRIVATE_KEY");
        address feeToSetter = vm.envAddress("FEE_TO_SETTER");
        address wsrx = vm.envAddress("WSRX");

        vm.startBroadcast(deployerKey);

        SentrixV2Factory factory = new SentrixV2Factory(feeToSetter);
        console.log("SentrixV2Factory deployed at:", address(factory));

        // Sanity check: the Pair INIT_CODE_HASH our Library expects must equal
        // the Factory's compiled-bytecode hash. If a future SentrixV2Pair edit
        // didn't re-patch the Library, this assertion catches it BEFORE any
        // pair gets created — better than learning at first swap.
        bytes32 expected = factory.pairCodeHash();
        bytes32 baked = _libraryHash(address(factory));
        require(expected == baked, "Deploy: INIT_CODE_HASH mismatch - re-run patch + recompile");

        SentrixV2Router02 router = new SentrixV2Router02(address(factory), wsrx);
        console.log("SentrixV2Router02 deployed at:", address(router));
        console.log("Wired:");
        console.log("  factory      =", address(factory));
        console.log("  WSRX         =", wsrx);
        console.log("  feeToSetter  =", feeToSetter);
        console.log("  pairCodeHash =", uint256(expected));

        console.log("");
        console.log("NEXT STEPS:");
        console.log(" 1. Verify both addresses on https://verify.sentrixchain.com");
        console.log(" 2. Update sentrix-labs/canonical-contracts/docs/addresses.md");
        console.log(" 3. Decide stablecoin pair + initial price ratio");
        console.log(" 4. Seed first pool from Eco Fund");

        vm.stopBroadcast();
    }

    // Recompute the hash that SentrixV2Library bakes in by faking a getReserves
    // call on a derived pair address via Library.pairFor — simpler: just trust
    // the constant. (Wrapper exists so we can extend the check later if needed.)
    function _libraryHash(address /*factory*/ ) internal pure returns (bytes32) {
        // The constant is private to the library; we recompute via the same
        // formula. If you change SentrixV2Pair, re-patch the Library const +
        // re-run this script.
        return _libraryConst();
    }

    function _libraryConst() internal pure returns (bytes32 h) {
        // Derive by inspecting the deployed Library — but Foundry can't import
        // a private constant. Use the same value the Library uses by deriving
        // a known-zero pairFor address and reverse-engineering, OR just hard-
        // code here matching the Library file.
        // Mirror of contracts/libraries/SentrixV2Library.sol#INIT_CODE_HASH.
        h = 0xa07454df7a2cdbc85b7d2304d76b30c66b098569d7b5944e840a26fbc21153f7;
    }
}
