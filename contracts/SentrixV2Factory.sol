// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISentrixV2Factory} from "./interfaces/ISentrixV2Factory.sol";

// SentrixV2Factory — UniswapV2-equivalent pair factory.
//
// IMPORTANT (2026-04-30): this is a STUB. Real implementation pending the
// dedicated DEX coding session per `README.md`. Do not deploy this stub
// to mainnet. See https://github.com/Uniswap/v2-core/blob/master/contracts/UniswapV2Factory.sol
// for the canonical reference being ported.
//
// TODO (next session):
//   - Port createPair() with CREATE2 salt = keccak256(abi.encodePacked(token0, token1))
//   - Wire SentrixV2Pair.initialize(token0, token1) post-create
//   - Implement allPairs storage + getPair O(1) lookup
//   - feeTo / feeToSetter access control
//   - PairCreated event emission
contract SentrixV2Factory is ISentrixV2Factory {
    address public override feeTo;
    address public override feeToSetter;

    mapping(address => mapping(address => address)) public override getPair;
    address[] public override allPairs;

    constructor(address _feeToSetter) {
        feeToSetter = _feeToSetter;
    }

    function allPairsLength() external view override returns (uint256) {
        return allPairs.length;
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        // TODO: implement CREATE2 deploy of SentrixV2Pair
        revert("SentrixV2Factory: NOT_IMPLEMENTED");
    }

    function setFeeTo(address _feeTo) external override {
        require(msg.sender == feeToSetter, "SentrixV2: FORBIDDEN");
        feeTo = _feeTo;
    }

    function setFeeToSetter(address _feeToSetter) external override {
        require(msg.sender == feeToSetter, "SentrixV2: FORBIDDEN");
        feeToSetter = _feeToSetter;
    }
}
