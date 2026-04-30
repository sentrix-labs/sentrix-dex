// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// WSRX (wrapped Sentrix native) — already deployed in canonical-contracts.
// Mirrors the WETH9 interface so standard tooling works.
interface IWSRX {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
}
