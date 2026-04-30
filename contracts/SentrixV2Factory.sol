// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISentrixV2Factory} from "./interfaces/ISentrixV2Factory.sol";
import {SentrixV2Pair} from "./SentrixV2Pair.sol";

// SentrixV2Factory — pair creator. CREATE2 with salt = keccak256(token0, token1)
// so the pair address is deterministically derivable off-chain (Library.pairFor
// uses this same salt to compute pair addresses without an on-chain lookup).
//
// The pair's INIT_CODE_HASH is whatever the compiled SentrixV2Pair bytecode
// hashes to. After this contract is compiled and deployed, `INIT_CODE_HASH`
// must be patched into SentrixV2Library before Router deploys, or pairFor()
// will return wrong addresses. Provided as `pairCodeHash()` view for that
// off-chain computation.
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

    // Helper for Library.pairFor — emits the bytecode hash that off-chain
    // tooling needs to embed in the Library constant.
    function pairCodeHash() external pure returns (bytes32) {
        return keccak256(type(SentrixV2Pair).creationCode);
    }

    function createPair(address tokenA, address tokenB) external override returns (address pair) {
        require(tokenA != tokenB, "SentrixV2: IDENTICAL_ADDRESSES");
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "SentrixV2: ZERO_ADDRESS");
        require(getPair[token0][token1] == address(0), "SentrixV2: PAIR_EXISTS");

        bytes memory bytecode = type(SentrixV2Pair).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(token0, token1));
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt)
        }
        require(pair != address(0), "SentrixV2: PAIR_DEPLOY_FAILED");

        SentrixV2Pair(pair).initialize(token0, token1);
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate reverse mapping for O(1) bidirectional lookup
        allPairs.push(pair);
        emit PairCreated(token0, token1, pair, allPairs.length);
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
