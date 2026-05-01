// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentrixV2Library} from "../contracts/libraries/SentrixV2Library.sol";

// Wrapper so internal library calls become external (so vm.expectRevert sees
// them at cheatcode depth + 1).
contract LibProbe {
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) external pure returns (uint256) {
        return SentrixV2Library.quote(amountA, reserveA, reserveB);
    }

    function sortTokens(address a, address b) external pure returns (address, address) {
        return SentrixV2Library.sortTokens(a, b);
    }
}

contract SentrixV2LibraryTest is Test {
    LibProbe probe;

    function setUp() public {
        probe = new LibProbe();
    }

    function test_quote_basic() public pure {
        // 100 of A given reserves 1000A:2000B → 200B
        uint256 b = SentrixV2Library.quote(100 ether, 1000 ether, 2000 ether);
        assertEq(b, 200 ether);
    }

    function test_quote_rejects_zero_amount() public {
        vm.expectRevert(bytes("SentrixV2Library: INSUFFICIENT_AMOUNT"));
        probe.quote(0, 1000 ether, 2000 ether);
    }

    function test_quote_rejects_zero_reserves() public {
        vm.expectRevert(bytes("SentrixV2Library: INSUFFICIENT_LIQUIDITY"));
        probe.quote(100 ether, 0, 2000 ether);
    }

    function test_amount_out_matches_uniswap_formula() public pure {
        // 100 in, reserves 1000:1000 → 996.... per UniV2 0.3% fee
        uint256 amountIn = 100 ether;
        uint256 reserveIn = 1000 ether;
        uint256 reserveOut = 1000 ether;
        uint256 out = SentrixV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
        // Reference: (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
        uint256 amountInWithFee = amountIn * 997;
        uint256 expected = (amountInWithFee * reserveOut) / (reserveIn * 1000 + amountInWithFee);
        assertEq(out, expected);
    }

    function test_amount_in_matches_uniswap_formula() public pure {
        // For 100 out with reserves 1000:1000
        uint256 amountOut = 100 ether;
        uint256 reserveIn = 1000 ether;
        uint256 reserveOut = 1000 ether;
        uint256 inAmt = SentrixV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
        // Reference: (reserveIn * amountOut * 1000) / ((reserveOut - amountOut) * 997) + 1
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        uint256 expected = (numerator / denominator) + 1;
        assertEq(inAmt, expected);
    }

    function test_sort_tokens_orders_canonically() public pure {
        (address a, address b) = SentrixV2Library.sortTokens(address(0x2), address(0x1));
        assertEq(a, address(0x1));
        assertEq(b, address(0x2));
    }

    function test_sort_tokens_rejects_zero() public {
        // sortTokens(0, 0x1) — sortTokens makes the smaller-addr first, so
        // token0 = 0, which fails the ZERO_ADDRESS guard. Note that calling
        // with (0, X) where X != 0 also reverts because sortTokens rejects
        // ANY pair with address(0). The guard checks token0 != 0 only, but
        // sortTokens will only place address(0) as token0 anyway since it's
        // the smallest possible address.
        vm.expectRevert(bytes("SentrixV2Library: ZERO_ADDRESS"));
        probe.sortTokens(address(0), address(0x1));
    }
}
