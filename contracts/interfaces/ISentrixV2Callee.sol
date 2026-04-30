// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Flash-swap callback. Pair invokes this on the swap initiator if data.length > 0,
// passing the requested out-amounts. Initiator must repay before the swap returns
// (canonical UniV2 flash-swap pattern).
interface ISentrixV2Callee {
    function sentrixV2Call(address sender, uint256 amount0, uint256 amount1, bytes calldata data) external;
}
