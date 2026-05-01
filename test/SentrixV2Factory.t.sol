// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentrixV2Factory} from "../contracts/SentrixV2Factory.sol";
import {SentrixV2Pair} from "../contracts/SentrixV2Pair.sol";
import {SentrixV2Library} from "../contracts/libraries/SentrixV2Library.sol";

contract SentrixV2FactoryTest is Test {
    SentrixV2Factory factory;
    address feeAdmin = address(0xFEE);
    address tokenA = address(0xA);
    address tokenB = address(0xB);

    function setUp() public {
        factory = new SentrixV2Factory(feeAdmin);
    }

    function test_create_pair_basic() public {
        address pair = factory.createPair(tokenA, tokenB);
        assertEq(factory.getPair(tokenA, tokenB), pair);
        assertEq(factory.getPair(tokenB, tokenA), pair); // reverse mapping
        assertEq(factory.allPairsLength(), 1);
    }

    function test_create_pair_rejects_identical() public {
        vm.expectRevert(bytes("SentrixV2: IDENTICAL_ADDRESSES"));
        factory.createPair(tokenA, tokenA);
    }

    function test_create_pair_rejects_zero() public {
        vm.expectRevert(bytes("SentrixV2: ZERO_ADDRESS"));
        factory.createPair(address(0), tokenA);
    }

    function test_create_pair_rejects_duplicate() public {
        factory.createPair(tokenA, tokenB);
        vm.expectRevert(bytes("SentrixV2: PAIR_EXISTS"));
        factory.createPair(tokenA, tokenB);
    }

    function test_set_fee_to() public {
        vm.prank(feeAdmin);
        factory.setFeeTo(address(0x123));
        assertEq(factory.feeTo(), address(0x123));
    }

    function test_set_fee_to_only_admin() public {
        vm.expectRevert(bytes("SentrixV2: FORBIDDEN"));
        factory.setFeeTo(address(0x123));
    }

    function test_set_fee_to_setter_rejects_zero() public {
        // The new audit fix: zero would brick fee admin forever.
        vm.prank(feeAdmin);
        vm.expectRevert(bytes("SentrixV2: ZERO_ADDRESS"));
        factory.setFeeToSetter(address(0));
    }

    function test_set_fee_to_setter_succession() public {
        address newAdmin = address(0xCAFE);
        vm.prank(feeAdmin);
        factory.setFeeToSetter(newAdmin);
        assertEq(factory.feeToSetter(), newAdmin);
        // Old admin can no longer set fee
        vm.prank(feeAdmin);
        vm.expectRevert(bytes("SentrixV2: FORBIDDEN"));
        factory.setFeeTo(address(0x999));
    }

    function test_pair_code_hash_matches_library_constant() public view {
        // The Library's INIT_CODE_HASH MUST equal the Factory's compile-time
        // pair bytecode hash. Drift = every pairFor() call returns wrong addr.
        bytes32 onChain = factory.pairCodeHash();
        bytes32 baked = 0xf7d8b4d1ce6c92cb3ce6b366dfb5977578db74e308b88facd5966df9e2a029dd;
        assertEq(onChain, baked, "pairCodeHash drifted from SentrixV2Library.INIT_CODE_HASH");
    }

    function test_pair_for_matches_create2() public {
        address derived = SentrixV2Library.pairFor(address(factory), tokenA, tokenB);
        address actual = factory.createPair(tokenA, tokenB);
        assertEq(derived, actual, "pairFor() does not match deployed pair address");
    }
}
