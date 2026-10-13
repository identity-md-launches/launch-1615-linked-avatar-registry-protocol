// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {LARPToken} from "../src/LARPToken.sol";

/// @dev An independent ledger models balances and approvals over arbitrary sequences of ERC-20 actions.
contract LARPHandler is Test {
    LARPToken private immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(LARPToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 1_000_000_000 * 10 ** 18;
    }

    function move(uint256 senderSeed, uint256 recipientSeed, uint256 amount) external {
        address from = actors[senderSeed % actors.length];
        address to = actors[recipientSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 maximum = expectedBalance[owner] < approved ? expectedBalance[owner] : approved;
        amount = bound(amount, 0, maximum);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[recipient] += amount;
        if (approved != type(uint256).max) expectedAllowance[owner][spender] -= amount;
    }

    function rejectedOverspend(uint256 senderSeed, uint256 recipientSeed) external {
        address from = actors[senderSeed % actors.length];
        address to = actors[recipientSeed % actors.length];
        uint256 balance = expectedBalance[from];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1)
        );
        vm.prank(from);
        token.transfer(to, balance + 1);
    }
}

contract LARPTokenInvariantTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    LARPToken private token;
    LARPHandler private handler;
    address[4] private actors;

    function setUp() public {
        token = new LARPToken();
        actors = [makeAddr("holder0"), makeAddr("holder1"), makeAddr("holder2"), makeAddr("holder3")];
        handler = new LARPHandler(token, actors);
        token.transfer(actors[0], SUPPLY);
        bytes4[] memory selectors = new bytes4[](4);
        selectors[0] = LARPHandler.move.selector;
        selectors[1] = LARPHandler.approve.selector;
        selectors[2] = LARPHandler.spend.selector;
        selectors[3] = LARPHandler.rejectedOverspend.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyAndAllBalancesMatchLedger() public view {
        uint256 sum;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            sum += balance;
        }
        assertEq(sum, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
    }

    function invariant_AllAllowancesMatchLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }
}
