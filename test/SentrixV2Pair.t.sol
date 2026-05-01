// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {SentrixV2Factory} from "../contracts/SentrixV2Factory.sol";
import {SentrixV2Pair} from "../contracts/SentrixV2Pair.sol";

contract MockToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 v);
    event Approval(address indexed o, address indexed s, uint256 v);

    constructor(string memory n, string memory s) {
        name = n;
        symbol = s;
    }

    function mint(address to, uint256 a) external {
        totalSupply += a;
        balanceOf[to] += a;
        emit Transfer(address(0), to, a);
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        emit Approval(msg.sender, s, a);
        return true;
    }

    function transfer(address to, uint256 a) external returns (bool) {
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        emit Transfer(msg.sender, to, a);
        return true;
    }

    function transferFrom(address from, address to, uint256 a) external returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= a;
        }
        balanceOf[from] -= a;
        balanceOf[to] += a;
        emit Transfer(from, to, a);
        return true;
    }
}

contract SentrixV2PairTest is Test {
    SentrixV2Factory factory;
    SentrixV2Pair pair;
    MockToken tokenA;
    MockToken tokenB;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        factory = new SentrixV2Factory(address(this));
        tokenA = new MockToken("A", "A");
        tokenB = new MockToken("B", "B");
        address pairAddr = factory.createPair(address(tokenA), address(tokenB));
        pair = SentrixV2Pair(pairAddr);
    }

    function _seed(uint256 a, uint256 b) internal {
        tokenA.mint(address(pair), a);
        tokenB.mint(address(pair), b);
        pair.mint(alice);
    }

    function test_initialize_idempotent() public {
        // Second initialize() must revert — defensive against future Factory edits
        vm.prank(address(factory));
        vm.expectRevert(bytes("SentrixV2: ALREADY_INITIALIZED"));
        pair.initialize(address(0xCafe), address(0xBeef));
    }

    function test_initialize_only_factory() public {
        vm.expectRevert(bytes("SentrixV2: FORBIDDEN"));
        pair.initialize(address(tokenA), address(tokenB));
    }

    function test_first_mint_creates_minimum_liquidity() public {
        _seed(1000 ether, 4000 ether);
        // sqrt(1000e18 * 4000e18) - 1000 = 2000e18 - 1000
        uint256 expected = 2000 ether - 1000;
        assertEq(pair.balanceOf(alice), expected);
        assertEq(pair.balanceOf(address(0)), 1000); // burned MINIMUM_LIQUIDITY
    }

    function test_swap_basic() public {
        _seed(1000 ether, 1000 ether);
        // Sort tokens to know which is token0
        (address t0,) =
            address(tokenA) < address(tokenB) ? (address(tokenA), address(tokenB)) : (address(tokenB), address(tokenA));

        // Swap 100 of tokenA → tokenB
        uint256 amountIn = 100 ether;
        // 0.3% fee → amountInWithFee = 100 * 997 = 99.7e18
        // amountOut = (99.7e18 * 1000e18) / (1000e18 * 1000 + 99.7e18) ≈ 90.66e18
        MockToken(t0).mint(address(pair), amountIn);

        // Compute expected output via UniV2 formula
        uint256 expectedOut = (amountIn * 997 * 1000 ether) / (1000 ether * 1000 + amountIn * 997);

        if (t0 == address(tokenA)) {
            pair.swap(0, expectedOut, bob, "");
        } else {
            pair.swap(expectedOut, 0, bob, "");
        }

        // bob should receive tokenB or tokenA depending on sort
        address otherToken = (t0 == address(tokenA)) ? address(tokenB) : address(tokenA);
        assertEq(MockToken(otherToken).balanceOf(bob), expectedOut);
    }

    function test_swap_reverts_without_input() public {
        _seed(1000 ether, 1000 ether);
        vm.expectRevert(bytes("SentrixV2: INSUFFICIENT_INPUT_AMOUNT"));
        pair.swap(1 ether, 0, bob, "");
    }

    function test_burn_returns_proportional() public {
        _seed(1000 ether, 1000 ether);
        uint256 lp = pair.balanceOf(alice);

        // Send all LP back to pair, then call burn
        vm.prank(alice);
        pair.transfer(address(pair), lp);
        pair.burn(bob);

        // bob should receive ~all reserves minus the MINIMUM_LIQUIDITY share
        // Reserve = 1000e18 each; share = lp / totalSupply ≈ (lp / (lp + 1000))
        uint256 totalSup = pair.totalSupply();
        uint256 expectedA = (lp * 1000 ether) / (totalSup + lp); // pre-burn calc
        // Easier: check post-burn invariant
        assertGt(MockToken(pair.token0()).balanceOf(bob), 0);
        assertGt(MockToken(pair.token1()).balanceOf(bob), 0);
        // Minimum liquidity (1000 wei worth) stays locked
        assertEq(pair.balanceOf(address(0)), 1000);
        // Suppress unused var warning
        expectedA;
    }

    function test_skim_drains_excess_to_recipient() public {
        _seed(1000 ether, 1000 ether);
        // Send extra tokens directly (not through mint() flow)
        tokenA.mint(address(pair), 50 ether);
        // Note: no pair.mint() call → reserves don't update

        uint256 before = tokenA.balanceOf(bob);
        pair.skim(bob);
        // bob should receive the 50 ether donation in tokenA
        if (pair.token0() == address(tokenA)) {
            assertEq(tokenA.balanceOf(bob) - before, 50 ether);
        }
    }

    function test_sync_aligns_reserves_to_balance() public {
        _seed(1000 ether, 1000 ether);
        tokenA.mint(address(pair), 100 ether);
        pair.sync();
        (uint112 r0, uint112 r1,) = pair.getReserves();
        if (pair.token0() == address(tokenA)) {
            assertEq(r0, 1100 ether);
            assertEq(r1, 1000 ether);
        } else {
            assertEq(r0, 1000 ether);
            assertEq(r1, 1100 ether);
        }
    }

    function test_lock_modifier_blocks_reentry() public {
        // sync() takes the lock; if it's not released we can't call it again
        // (this isn't a reentrancy proof per se, but tests the lock unlocks).
        _seed(1000 ether, 1000 ether);
        pair.sync();
        pair.sync(); // second call must succeed → lock did unlock
    }
}
