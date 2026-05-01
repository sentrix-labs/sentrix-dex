// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISentrixV2Pair} from "../interfaces/ISentrixV2Pair.sol";

// Pure helpers — quote, getAmountOut/In, pairFor without on-chain lookup.
//
// `INIT_CODE_HASH` MUST equal `keccak256(type(SentrixV2Pair).creationCode)` of
// the compiled Pair contract that the deployed Factory uses. After Factory is
// deployed (or redeployed), call Factory.pairCodeHash() and patch the constant
// below before deploying Router. If the hash is wrong, pairFor() returns
// addresses that don't match the actual deployed pairs and every Router call
// fails with "INVALID_PAIR" / OOG.
library SentrixV2Library {
    // keccak256(type(SentrixV2Pair).creationCode) of the audit-passed Pair
    // bytecode (post 2026-04-30 audit hardening — initialize() guard,
    // chainid-aware DOMAIN_SEPARATOR). Patched at deploy time. See Deploy.s.sol.
    bytes32 internal constant INIT_CODE_HASH =
        0x87b7369bc2bbcffa756dcecf2bb85130662c78397819f0c4a98176eb8d4bcb60;

    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, "SentrixV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), "SentrixV2Library: ZERO_ADDRESS");
    }

    // Deterministic CREATE2 pair address — no SLOAD, pure computation.
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff", factory, keccak256(abi.encodePacked(token0, token1)), INIT_CODE_HASH
                        )
                    )
                )
            )
        );
    }

    function getReserves(address factory, address tokenA, address tokenB)
        internal
        view
        returns (uint256 reserveA, uint256 reserveB)
    {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = ISentrixV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, "SentrixV2Library: INSUFFICIENT_AMOUNT");
        require(reserveA > 0 && reserveB > 0, "SentrixV2Library: INSUFFICIENT_LIQUIDITY");
        amountB = amountA * reserveB / reserveA;
    }

    // 0.30% fee (997/1000) — same as UniV2 default.
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountOut)
    {
        require(amountIn > 0, "SentrixV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "SentrixV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        amountOut = numerator / denominator;
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256 amountIn)
    {
        require(amountOut > 0, "SentrixV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(reserveIn > 0 && reserveOut > 0, "SentrixV2Library: INSUFFICIENT_LIQUIDITY");
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function getAmountsOut(address factory, uint256 amountIn, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "SentrixV2Library: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    function getAmountsIn(address factory, uint256 amountOut, address[] memory path)
        internal
        view
        returns (uint256[] memory amounts)
    {
        require(path.length >= 2, "SentrixV2Library: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}
