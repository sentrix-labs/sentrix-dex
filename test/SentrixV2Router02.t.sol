// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {SentrixV2Factory} from "../contracts/SentrixV2Factory.sol";
import {SentrixV2Pair} from "../contracts/SentrixV2Pair.sol";
import {SentrixV2Router02} from "../contracts/SentrixV2Router02.sol";
import {SentrixV2Library} from "../contracts/libraries/SentrixV2Library.sol";

contract MockToken {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    event Transfer(address indexed from, address indexed to, uint256 v);

    constructor(string memory n, string memory s) {
        name = n;
        symbol = s;
    }

    function mint(address to, uint256 a) public {
        totalSupply += a;
        balanceOf[to] += a;
        emit Transfer(address(0), to, a);
    }

    function approve(address s, uint256 a) external returns (bool) {
        allowance[msg.sender][s] = a;
        return true;
    }

    function transfer(address to, uint256 a) external virtual returns (bool) {
        balanceOf[msg.sender] -= a;
        balanceOf[to] += a;
        emit Transfer(msg.sender, to, a);
        return true;
    }

    function transferFrom(address from, address to, uint256 a) external virtual returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= a;
        }
        balanceOf[from] -= a;
        balanceOf[to] += a;
        emit Transfer(from, to, a);
        return true;
    }
}

// Minimal WSRX matching the IWSRX interface (deposit / transfer / withdraw).
contract MockWSRX is MockToken {
    constructor() MockToken("Wrapped SRX", "WSRX") {}

    function deposit() external payable {
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }

    function withdraw(uint256 amount) external {
        balanceOf[msg.sender] -= amount;
        totalSupply -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "WSRX: WITHDRAW_FAILED");
        emit Transfer(msg.sender, address(0), amount);
    }

    receive() external payable {
        // Native SRX deposit fallback (so EOA sends auto-wrap).
        balanceOf[msg.sender] += msg.value;
        totalSupply += msg.value;
        emit Transfer(address(0), msg.sender, msg.value);
    }
}

// Fee-on-transfer mock: takes 1% of every transfer.
contract FoTToken is MockToken {
    constructor() MockToken("Fee", "FOT") {}

    function transfer(address to, uint256 a) external override returns (bool) {
        uint256 fee = a / 100;
        uint256 net = a - fee;
        balanceOf[msg.sender] -= a;
        balanceOf[to] += net;
        balanceOf[address(0xFEE)] += fee;
        emit Transfer(msg.sender, to, net);
        emit Transfer(msg.sender, address(0xFEE), fee);
        return true;
    }

    function transferFrom(address from, address to, uint256 a) external override returns (bool) {
        if (allowance[from][msg.sender] != type(uint256).max) {
            allowance[from][msg.sender] -= a;
        }
        uint256 fee = a / 100;
        uint256 net = a - fee;
        balanceOf[from] -= a;
        balanceOf[to] += net;
        balanceOf[address(0xFEE)] += fee;
        emit Transfer(from, to, net);
        emit Transfer(from, address(0xFEE), fee);
        return true;
    }
}

contract SentrixV2Router02Test is Test {
    SentrixV2Factory factory;
    SentrixV2Router02 router;
    MockWSRX wsrx;
    MockToken tokenA;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        factory = new SentrixV2Factory(address(this));
        wsrx = new MockWSRX();
        router = new SentrixV2Router02(address(factory), address(wsrx));
        tokenA = new MockToken("A", "A");
        // Pre-fund alice with native SRX
        vm.deal(alice, 100 ether);
    }

    function test_add_liquidity_srx_first_pool() public {
        tokenA.mint(alice, 1000 ether);
        vm.prank(alice);
        tokenA.approve(address(router), type(uint256).max);

        vm.prank(alice);
        (uint256 amountToken, uint256 amountSRX, uint256 liquidity) = router.addLiquiditySRX{value: 10 ether}(
            address(tokenA),
            1000 ether, // amountTokenDesired
            1, // amountTokenMin
            1, // amountSRXMin
            alice,
            block.timestamp + 1
        );

        assertEq(amountToken, 1000 ether);
        assertEq(amountSRX, 10 ether);
        // liquidity = sqrt(1000e18 * 10e18) - 1000 = ~100e18 - 1000
        assertGt(liquidity, 0);
    }

    function test_swap_exact_srx_for_tokens() public {
        // Seed pool first
        tokenA.mint(alice, 1000 ether);
        vm.prank(alice);
        tokenA.approve(address(router), type(uint256).max);
        vm.prank(alice);
        router.addLiquiditySRX{value: 10 ether}(
            address(tokenA), 1000 ether, 1, 1, alice, block.timestamp + 1
        );

        // Now bob swaps 1 SRX → tokenA
        vm.deal(bob, 1 ether);
        address[] memory path = new address[](2);
        path[0] = address(wsrx);
        path[1] = address(tokenA);

        uint256 before = tokenA.balanceOf(bob);
        vm.prank(bob);
        router.swapExactSRXForTokens{value: 1 ether}(0, path, bob, block.timestamp + 1);
        assertGt(tokenA.balanceOf(bob), before);
    }

    function test_swap_exact_tokens_for_srx() public {
        tokenA.mint(alice, 1000 ether);
        vm.prank(alice);
        tokenA.approve(address(router), type(uint256).max);
        vm.prank(alice);
        router.addLiquiditySRX{value: 10 ether}(
            address(tokenA), 1000 ether, 1, 1, alice, block.timestamp + 1
        );

        tokenA.mint(bob, 100 ether);
        vm.prank(bob);
        tokenA.approve(address(router), type(uint256).max);

        address[] memory path = new address[](2);
        path[0] = address(tokenA);
        path[1] = address(wsrx);

        uint256 before = bob.balance;
        vm.prank(bob);
        router.swapExactTokensForSRX(50 ether, 0, path, bob, block.timestamp + 1);
        assertGt(bob.balance, before);
    }

    function test_remove_liquidity_srx() public {
        tokenA.mint(alice, 1000 ether);
        vm.prank(alice);
        tokenA.approve(address(router), type(uint256).max);
        vm.prank(alice);
        (,, uint256 liquidity) = router.addLiquiditySRX{value: 10 ether}(
            address(tokenA), 1000 ether, 1, 1, alice, block.timestamp + 1
        );

        // Approve router to pull LP, then remove
        address pair = factory.getPair(address(tokenA), address(wsrx));
        vm.prank(alice);
        SentrixV2Pair(pair).approve(address(router), liquidity);

        uint256 srxBefore = alice.balance;
        vm.prank(alice);
        router.removeLiquiditySRX(address(tokenA), liquidity, 1, 1, alice, block.timestamp + 1);
        assertGt(alice.balance, srxBefore);
    }

    function test_swap_expired_deadline_reverts() public {
        address[] memory path = new address[](2);
        path[0] = address(wsrx);
        path[1] = address(tokenA);

        vm.deal(bob, 1 ether);
        vm.prank(bob);
        vm.expectRevert(bytes("SentrixV2Router: EXPIRED"));
        router.swapExactSRXForTokens{value: 1 ether}(0, path, bob, block.timestamp - 1);
    }

    function test_fee_on_transfer_swap() public {
        // Verify the new audit-added FoT path actually settles successfully.
        FoTToken fot = new FoTToken();
        fot.mint(alice, 1000 ether);
        vm.prank(alice);
        fot.approve(address(router), type(uint256).max);
        vm.prank(alice);
        router.addLiquiditySRX{value: 10 ether}(
            address(fot), 1000 ether, 1, 1, alice, block.timestamp + 1
        );

        // Bob swaps 1 SRX into FoT via the FoT-aware path.
        vm.deal(bob, 1 ether);
        address[] memory path = new address[](2);
        path[0] = address(wsrx);
        path[1] = address(fot);

        uint256 before = fot.balanceOf(bob);
        vm.prank(bob);
        router.swapExactSRXForTokensSupportingFeeOnTransferTokens{value: 1 ether}(
            0, path, bob, block.timestamp + 1
        );
        assertGt(fot.balanceOf(bob), before);
    }
}
