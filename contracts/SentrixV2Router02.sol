// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ISentrixV2Factory} from "./interfaces/ISentrixV2Factory.sol";
import {ISentrixV2Pair} from "./interfaces/ISentrixV2Pair.sol";
import {IERC20Minimal} from "./interfaces/IERC20Minimal.sol";
import {IWSRX} from "./interfaces/IWSRX.sol";
import {SentrixV2Library} from "./libraries/SentrixV2Library.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";

// SentrixV2Router02 — UniswapV2Router02 functional equivalent.
//
// Naming: SRX takes the place of ETH throughout (e.g. swapExactSRXForTokens
// instead of swapExactETHForTokens). WSRX is the canonical wrapped-SRX SRC-20
// (deployed in `sentrix-labs/canonical-contracts`).
contract SentrixV2Router02 {
    address public immutable factory;
    address public immutable WSRX;

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "SentrixV2Router: EXPIRED");
        _;
    }

    constructor(address _factory, address _WSRX) {
        factory = _factory;
        WSRX = _WSRX;
    }

    // Allow Router to receive native SRX from WSRX.withdraw()
    receive() external payable {
        require(msg.sender == WSRX, "SentrixV2Router: ONLY_WSRX");
    }

    // ── Add liquidity ────────────────────────────────────────────────

    function _addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin
    ) internal returns (uint256 amountA, uint256 amountB) {
        if (ISentrixV2Factory(factory).getPair(tokenA, tokenB) == address(0)) {
            ISentrixV2Factory(factory).createPair(tokenA, tokenB);
        }
        (uint256 reserveA, uint256 reserveB) = SentrixV2Library.getReserves(factory, tokenA, tokenB);
        if (reserveA == 0 && reserveB == 0) {
            (amountA, amountB) = (amountADesired, amountBDesired);
        } else {
            uint256 amountBOptimal = SentrixV2Library.quote(amountADesired, reserveA, reserveB);
            if (amountBOptimal <= amountBDesired) {
                require(amountBOptimal >= amountBMin, "SentrixV2Router: INSUFFICIENT_B_AMOUNT");
                (amountA, amountB) = (amountADesired, amountBOptimal);
            } else {
                uint256 amountAOptimal = SentrixV2Library.quote(amountBDesired, reserveB, reserveA);
                assert(amountAOptimal <= amountADesired);
                require(amountAOptimal >= amountAMin, "SentrixV2Router: INSUFFICIENT_A_AMOUNT");
                (amountA, amountB) = (amountAOptimal, amountBDesired);
            }
        }
    }

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256 amountA, uint256 amountB, uint256 liquidity) {
        (amountA, amountB) = _addLiquidity(tokenA, tokenB, amountADesired, amountBDesired, amountAMin, amountBMin);
        address pair = SentrixV2Library.pairFor(factory, tokenA, tokenB);
        TransferHelper.safeTransferFrom(tokenA, msg.sender, pair, amountA);
        TransferHelper.safeTransferFrom(tokenB, msg.sender, pair, amountB);
        liquidity = ISentrixV2Pair(pair).mint(to);
    }

    function addLiquiditySRX(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountSRXMin,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) returns (uint256 amountToken, uint256 amountSRX, uint256 liquidity) {
        (amountToken, amountSRX) =
            _addLiquidity(token, WSRX, amountTokenDesired, msg.value, amountTokenMin, amountSRXMin);
        address pair = SentrixV2Library.pairFor(factory, token, WSRX);
        TransferHelper.safeTransferFrom(token, msg.sender, pair, amountToken);
        IWSRX(WSRX).deposit{value: amountSRX}();
        require(IWSRX(WSRX).transfer(pair, amountSRX), "SentrixV2Router: WSRX_TRANSFER_FAILED");
        liquidity = ISentrixV2Pair(pair).mint(to);
        // Refund dust SRX
        if (msg.value > amountSRX) TransferHelper.safeTransferSRX(msg.sender, msg.value - amountSRX);
    }

    // ── Remove liquidity ─────────────────────────────────────────────

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountA, uint256 amountB) {
        address pair = SentrixV2Library.pairFor(factory, tokenA, tokenB);
        ISentrixV2Pair(pair).transferFrom(msg.sender, pair, liquidity);
        (uint256 amount0, uint256 amount1) = ISentrixV2Pair(pair).burn(to);
        (address token0,) = SentrixV2Library.sortTokens(tokenA, tokenB);
        (amountA, amountB) = tokenA == token0 ? (amount0, amount1) : (amount1, amount0);
        require(amountA >= amountAMin, "SentrixV2Router: INSUFFICIENT_A_AMOUNT");
        require(amountB >= amountBMin, "SentrixV2Router: INSUFFICIENT_B_AMOUNT");
    }

    function removeLiquiditySRX(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountSRXMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountToken, uint256 amountSRX) {
        (amountToken, amountSRX) = removeLiquidity(
            token, WSRX, liquidity, amountTokenMin, amountSRXMin, address(this), deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWSRX(WSRX).withdraw(amountSRX);
        TransferHelper.safeTransferSRX(to, amountSRX);
    }

    // ── Swap ─────────────────────────────────────────────────────────

    // Internal: walk the path and swap pair-by-pair.
    function _swap(uint256[] memory amounts, address[] memory path, address _to) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = SentrixV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < path.length - 2 ? SentrixV2Library.pairFor(factory, output, path[i + 2]) : _to;
            ISentrixV2Pair(SentrixV2Library.pairFor(factory, input, output))
                .swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = SentrixV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "SentrixV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SentrixV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        amounts = SentrixV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "SentrixV2Router: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SentrixV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, to);
    }

    function swapExactSRXForTokens(uint256 amountOutMin, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WSRX, "SentrixV2Router: INVALID_PATH");
        amounts = SentrixV2Library.getAmountsOut(factory, msg.value, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "SentrixV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        IWSRX(WSRX).deposit{value: amounts[0]}();
        require(
            IWSRX(WSRX).transfer(SentrixV2Library.pairFor(factory, path[0], path[1]), amounts[0]),
            "SentrixV2Router: WSRX_TRANSFER_FAILED"
        );
        _swap(amounts, path, to);
    }

    function swapTokensForExactSRX(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WSRX, "SentrixV2Router: INVALID_PATH");
        amounts = SentrixV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= amountInMax, "SentrixV2Router: EXCESSIVE_INPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SentrixV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWSRX(WSRX).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferSRX(to, amounts[amounts.length - 1]);
    }

    function swapExactTokensForSRX(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) returns (uint256[] memory amounts) {
        require(path[path.length - 1] == WSRX, "SentrixV2Router: INVALID_PATH");
        amounts = SentrixV2Library.getAmountsOut(factory, amountIn, path);
        require(amounts[amounts.length - 1] >= amountOutMin, "SentrixV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SentrixV2Library.pairFor(factory, path[0], path[1]), amounts[0]
        );
        _swap(amounts, path, address(this));
        IWSRX(WSRX).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferSRX(to, amounts[amounts.length - 1]);
    }

    function swapSRXForExactTokens(uint256 amountOut, address[] calldata path, address to, uint256 deadline)
        external
        payable
        ensure(deadline)
        returns (uint256[] memory amounts)
    {
        require(path[0] == WSRX, "SentrixV2Router: INVALID_PATH");
        amounts = SentrixV2Library.getAmountsIn(factory, amountOut, path);
        require(amounts[0] <= msg.value, "SentrixV2Router: EXCESSIVE_INPUT_AMOUNT");
        IWSRX(WSRX).deposit{value: amounts[0]}();
        require(
            IWSRX(WSRX).transfer(SentrixV2Library.pairFor(factory, path[0], path[1]), amounts[0]),
            "SentrixV2Router: WSRX_TRANSFER_FAILED"
        );
        _swap(amounts, path, to);
        if (msg.value > amounts[0]) TransferHelper.safeTransferSRX(msg.sender, msg.value - amounts[0]);
    }

    // ── Fee-on-transfer-aware variants ───────────────────────────────
    //
    // Some tokens take a transfer fee (USDT-future, RFI/SafeMoon-style). The
    // standard swap path enforces an exact input → exact output mapping that
    // breaks when the actual delivered amount drops mid-flight. These variants
    // always read the *post-transfer* pair balance and let the AMM math derive
    // the real output. Behaviour mirrors UniswapV2Router02's "Supporting"
    // helpers — required for deflationary tokens to swap at all.

    function _swapSupportingFeeOnTransferTokens(address[] memory path, address _to) internal {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = SentrixV2Library.sortTokens(input, output);
            ISentrixV2Pair pair = ISentrixV2Pair(SentrixV2Library.pairFor(factory, input, output));
            uint256 amountInput;
            uint256 amountOutput;
            {
                (uint112 reserve0, uint112 reserve1,) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) =
                    input == token0 ? (uint256(reserve0), uint256(reserve1)) : (uint256(reserve1), uint256(reserve0));
                amountInput = IERC20Minimal(input).balanceOf(address(pair)) - reserveInput;
                amountOutput = SentrixV2Library.getAmountOut(amountInput, reserveInput, reserveOutput);
            }
            (uint256 amount0Out, uint256 amount1Out) =
                input == token0 ? (uint256(0), amountOutput) : (amountOutput, uint256(0));
            address to = i < path.length - 2 ? SentrixV2Library.pairFor(factory, output, path[i + 2]) : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SentrixV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        uint256 balanceBefore = IERC20Minimal(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20Minimal(path[path.length - 1]).balanceOf(to) - balanceBefore >= amountOutMin,
            "SentrixV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactSRXForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable ensure(deadline) {
        require(path[0] == WSRX, "SentrixV2Router: INVALID_PATH");
        uint256 amountIn = msg.value;
        IWSRX(WSRX).deposit{value: amountIn}();
        require(
            IWSRX(WSRX).transfer(SentrixV2Library.pairFor(factory, path[0], path[1]), amountIn),
            "SentrixV2Router: WSRX_TRANSFER_FAILED"
        );
        uint256 balanceBefore = IERC20Minimal(path[path.length - 1]).balanceOf(to);
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20Minimal(path[path.length - 1]).balanceOf(to) - balanceBefore >= amountOutMin,
            "SentrixV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    function swapExactTokensForSRXSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        require(path[path.length - 1] == WSRX, "SentrixV2Router: INVALID_PATH");
        TransferHelper.safeTransferFrom(
            path[0], msg.sender, SentrixV2Library.pairFor(factory, path[0], path[1]), amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20Minimal(WSRX).balanceOf(address(this));
        require(amountOut >= amountOutMin, "SentrixV2Router: INSUFFICIENT_OUTPUT_AMOUNT");
        IWSRX(WSRX).withdraw(amountOut);
        TransferHelper.safeTransferSRX(to, amountOut);
    }

    function removeLiquiditySRXSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountSRXMin,
        address to,
        uint256 deadline
    ) public ensure(deadline) returns (uint256 amountSRX) {
        (, amountSRX) = removeLiquidity(token, WSRX, liquidity, amountTokenMin, amountSRXMin, address(this), deadline);
        // For deflationary tokens, the actual balance is what we forward; the
        // amountToken returned by the pair burn may have included a transfer
        // tax that already left this contract.
        TransferHelper.safeTransfer(token, to, IERC20Minimal(token).balanceOf(address(this)));
        IWSRX(WSRX).withdraw(amountSRX);
        TransferHelper.safeTransferSRX(to, amountSRX);
    }

    // ── Permit-gated liquidity removal ───────────────────────────────
    //
    // Lets the LP signer skip the separate `approve()` tx — they sign an EIP-2612
    // permit off-chain and the router consumes it inline. Standard UniV2 helper.

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB) {
        address pair = SentrixV2Library.pairFor(factory, tokenA, tokenB);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        ISentrixV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountA, amountB) = removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, to, deadline);
    }

    function removeLiquiditySRXWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountSRXMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountSRX) {
        address pair = SentrixV2Library.pairFor(factory, token, WSRX);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        ISentrixV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        (amountToken, amountSRX) = removeLiquiditySRX(token, liquidity, amountTokenMin, amountSRXMin, to, deadline);
    }

    function removeLiquiditySRXWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountSRXMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountSRX) {
        address pair = SentrixV2Library.pairFor(factory, token, WSRX);
        uint256 value = approveMax ? type(uint256).max : liquidity;
        ISentrixV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        amountSRX = removeLiquiditySRXSupportingFeeOnTransferTokens(
            token, liquidity, amountTokenMin, amountSRXMin, to, deadline
        );
    }

    // ── Pure pass-throughs ───────────────────────────────────────────

    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256 amountB) {
        return SentrixV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        return SentrixV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountIn)
    {
        return SentrixV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] calldata path) public view returns (uint256[] memory amounts) {
        return SentrixV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] calldata path) public view returns (uint256[] memory amounts) {
        return SentrixV2Library.getAmountsIn(factory, amountOut, path);
    }
}
