// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {LARPToken} from "src/LARPToken.sol";

/// @notice Boundary regressions and properties that compare observable outcomes of different call sequences.
/// forge-config: default.fuzz.runs = 1000
contract LARPTokenPropertiesTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    LARPToken private token;
    address private alice = makeAddr("property alice");
    address private bob = makeAddr("property bob");
    address private spender = makeAddr("property spender");

    function setUp() public {
        token = new LARPToken();
    }

    function test_OneWeiCanBeTransferredAndReturned() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 1);
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);
        vm.prank(alice);
        assertTrue(token.transfer(address(this), 1));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumFiniteApprovalIsDecreased() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY - 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 1 - SUPPLY);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_InfiniteApprovalCanBeLoweredAndRevokedAfterSpending() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max);

        assertTrue(token.approve(spender, 2));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 2, 3));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 3);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.allowance(address(this), spender), 2);

        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 1);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 2);
        assertEq(token.balanceOf(address(this)), SUPPLY - 2);
    }

    function test_SelfDelegationRequiresItsOwnApproval() public {
        token.transfer(alice, 2);
        vm.prank(alice);
        token.approve(spender, type(uint256).max);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transferFrom(alice, bob, 1);

        vm.prank(alice);
        token.approve(alice, 1);
        vm.prank(alice);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, alice), 0);
        assertEq(token.allowance(alice, spender), type(uint256).max);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(bob), 1);
    }

    function test_SpenderMayReceiveTheEntireDelegatedBalance() public {
        token.approve(spender, SUPPLY);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), spender, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(spender), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroDelegatedTransferEmitsEventAndPreservesEveryApprovalKind() public {
        uint256[3] memory approvals = [uint256(0), 1, type(uint256).max];
        for (uint256 i; i < approvals.length; ++i) {
            vm.prank(alice);
            token.approve(spender, approvals[i]);
            vm.expectEmit(true, true, false, true, address(token));
            emit IERC20.Transfer(alice, bob, 0);
            vm.prank(spender);
            assertTrue(token.transferFrom(alice, bob, 0));
            assertEq(token.allowance(alice, spender), approvals[i]);
            assertEq(token.balanceOf(alice), 0);
            assertEq(token.balanceOf(bob), 0);
        }
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroApprovalToZeroSpenderStillReverts() public {
        token.approve(spender, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 0);
        assertEq(token.allowance(address(this), address(0)), 0);
        assertEq(token.allowance(address(this), spender), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_SelfTransfersCannotBypassInsufficientBalance() public {
        token.transfer(alice, 1);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(alice);
        token.transfer(alice, 2);

        vm.prank(alice);
        token.approve(spender, 2);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2));
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.allowance(alice, spender), 2);
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_MaximumDelegatedTransferRejectsWithoutConsumingUnlimitedApproval() public {
        token.approve(spender, type(uint256).max);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferToTokenContractDoesNotBurnSupply() public {
        assertTrue(token.transfer(address(token), 1));
        token.approve(spender, SUPPLY - 1);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(token), SUPPLY - 1));
        assertEq(token.balanceOf(address(token)), SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.allowance(address(this), spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function testFuzz_RoundTripRestoresBalancesWithPrefundedRecipient(
        uint256 aliceBalance,
        uint256 bobBalance,
        uint256 amount
    ) public {
        aliceBalance = bound(aliceBalance, 0, SUPPLY);
        bobBalance = bound(bobBalance, 0, SUPPLY - aliceBalance);
        amount = bound(amount, 0, aliceBalance);
        token.transfer(alice, aliceBalance);
        token.transfer(bob, bobBalance);
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.balanceOf(alice), aliceBalance - amount);
        assertEq(token.balanceOf(bob), bobBalance + amount);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(address(this)), SUPPLY - aliceBalance - bobBalance);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SplitDelegatedTransferMatchesSingleTransfer(uint256 amount, uint256 first, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        first = bound(first, 0, amount);
        uint256 approved = infinite ? type(uint256).max : amount;
        LARPToken split = new LARPToken();
        token.approve(spender, approved);
        split.approve(spender, approved);

        vm.startPrank(spender);
        assertTrue(token.transferFrom(address(this), alice, amount));
        assertTrue(split.transferFrom(address(this), alice, first));
        assertTrue(split.transferFrom(address(this), alice, amount - first));
        vm.stopPrank();

        assertEq(split.balanceOf(alice), token.balanceOf(alice));
        assertEq(split.balanceOf(address(this)), token.balanceOf(address(this)));
        assertEq(split.allowance(address(this), spender), token.allowance(address(this), spender));
        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(address(this), spender), infinite ? type(uint256).max : 0);
        assertEq(split.totalSupply(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_ApprovalReplacementIsIdempotentAndIsolated(
        uint256 first,
        uint256 second,
        uint256 otherOwner,
        uint256 otherSpender
    ) public {
        token.approve(spender, first);
        token.approve(bob, otherSpender);
        vm.prank(alice);
        token.approve(spender, otherOwner);

        // Repeating an approval replaces it again; it must never accumulate authority.
        for (uint256 i; i < 2; ++i) {
            vm.expectEmit(true, true, false, true, address(token));
            emit IERC20.Approval(address(this), spender, second);
            assertTrue(token.approve(spender, second));
            assertEq(token.allowance(address(this), spender), second);
            assertEq(token.allowance(address(this), bob), otherSpender);
            assertEq(token.allowance(alice, spender), otherOwner);
        }
        assertEq(token.allowance(spender, address(this)), 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_FailedDelegatedTransferCanRetryAfterFunding(uint256 balance, uint256 amount, bool infinite)
        public
    {
        balance = bound(balance, 0, SUPPLY - 1);
        amount = bound(amount, balance + 1, SUPPLY);
        uint256 approved = infinite ? type(uint256).max : amount;
        token.transfer(alice, balance);
        vm.prank(alice);
        token.approve(spender, approved);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, amount));
        vm.prank(spender);
        token.transferFrom(alice, bob, amount);
        assertEq(token.allowance(alice, spender), approved);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);

        // Retry the exact same call after funding; the failed call must leave no partial debit.
        token.transfer(alice, amount - balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.allowance(alice, spender), infinite ? type(uint256).max : 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_DirectSpendingDoesNotConsumeDelegatedApproval(uint256 amount, uint256 approved) public {
        amount = bound(amount, 0, SUPPLY);
        approved = bound(approved, amount, type(uint256).max);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.approve(spender, approved);
        vm.prank(alice);
        assertTrue(token.transfer(bob, amount));
        assertEq(token.allowance(alice, spender), approved);
        vm.prank(bob);
        assertTrue(token.transfer(alice, amount));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, amount));
        assertEq(token.allowance(alice, spender), approved == type(uint256).max ? approved : approved - amount);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
