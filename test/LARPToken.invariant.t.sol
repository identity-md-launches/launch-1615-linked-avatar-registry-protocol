// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {LARPToken} from "../src/LARPToken.sol";

/// @dev An independent ledger models balances and approvals over arbitrary sequences of ERC-20 actions.
contract LARPHandler is Test {
    uint256 private constant SUPPLY = 1_000_000_000 * 10 ** 18;
    LARPToken private immutable token;
    address[4] public actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;
    uint256 public positiveTransfers;
    uint256 public positiveDelegatedTransfers;
    uint256 public rejectedCalls;

    constructor(LARPToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = SUPPLY;
    }

    function move(uint256 senderSeed, uint256 recipientSeed, uint256 amount) external {
        address from = actors[senderSeed % actors.length];
        address to = actors[recipientSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        _move(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        _approve(owner, spender, amount);
    }

    function spend(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 maximum = expectedBalance[owner] < approved ? expectedBalance[owner] : approved;
        amount = bound(amount, 0, maximum);
        _spend(owner, spender, recipient, amount);
    }

    /// @dev Force the approval states that unrestricted uint256 fuzzing rarely reaches.
    function approveBoundary(uint256 ownerSeed, uint256 spenderSeed, uint8 edge) external {
        uint256[5] memory amounts = [uint256(0), 1, SUPPLY, type(uint256).max - 1, type(uint256).max];
        _approve(actors[ownerSeed % actors.length], actors[spenderSeed % actors.length], amounts[edge % 5]);
    }

    /// @dev Every call spends a positive amount, including exact and unlimited approvals.
    function approveAndSpend(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 recipientSeed,
        uint256 amount,
        bool infinite
    ) external {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        amount = bound(amount, 1, expectedBalance[owner]);
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        _spend(owner, spender, recipient, amount);
    }

    /// @dev Consolidation and subsequent redistribution must work at the full-balance boundary.
    function moveAll(uint256 senderSeed, uint256 recipientSeed) external {
        address from = _fundedActor(senderSeed);
        address to = _otherActor(from, recipientSeed);
        _move(from, to, expectedBalance[from]);
        assertEq(token.balanceOf(from), 0, "full transfer did not empty sender");
    }

    function roundTrip(uint256 senderSeed, uint256 recipientSeed, uint256 amount) external {
        address from = _fundedActor(senderSeed);
        address to = _otherActor(from, recipientSeed);
        uint256 fromBefore = expectedBalance[from];
        uint256 toBefore = expectedBalance[to];
        amount = bound(amount, 1, fromBefore);
        _move(from, to, amount);
        _move(to, from, amount);
        assertEq(token.balanceOf(from), fromBefore, "round trip changed sender balance");
        assertEq(token.balanceOf(to), toBefore, "round trip changed recipient balance");
    }

    function rejectedUnapprovedSpend(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed, uint256 approved)
        external
    {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        // The owner can afford the transfer, so only the authorization can reject it.
        approved = bound(approved, 0, expectedBalance[owner] - 1);
        _approve(owner, spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, recipient, approved + 1);
        ++rejectedCalls;
    }

    function rejectedDelegatedOverspend(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed, bool infinite)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 approved = infinite ? type(uint256).max : balance + 1;
        _approve(owner, spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, balance + 1)
        );
        vm.prank(spender);
        token.transferFrom(owner, recipient, balance + 1);
        assertEq(token.allowance(owner, spender), approved, "failed spend consumed approval");
        ++rejectedCalls;
    }

    function rejectedZeroRecipient(
        uint256 ownerSeed,
        uint256 spenderSeed,
        uint256 amount,
        bool delegated,
        bool infinite
    ) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[owner]);
        if (delegated) {
            _approve(owner, spender, infinite ? type(uint256).max : amount);
        }
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        if (delegated) {
            vm.prank(spender);
            token.transferFrom(owner, address(0), amount);
        } else {
            vm.prank(owner);
            token.transfer(address(0), amount);
        }
        ++rejectedCalls;
    }

    function rejectedZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(owner);
        token.approve(address(0), amount);
        ++rejectedCalls;
    }

    function revokeAndReject(uint256 ownerSeed, uint256 spenderSeed, uint256 recipientSeed) external {
        address owner = _fundedActor(ownerSeed);
        address spender = actors[spenderSeed % actors.length];
        address recipient = actors[recipientSeed % actors.length];
        _approve(owner, spender, 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(owner, recipient, 1);
        ++rejectedCalls;
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
        ++rejectedCalls;
    }

    function _move(address from, address to, uint256 amount) private {
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
        assertEq(token.balanceOf(from), expectedBalance[from]);
        assertEq(token.balanceOf(to), expectedBalance[to]);
        if (amount > 0) ++positiveTransfers;
    }

    function _approve(address owner, address spender, uint256 amount) private {
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
        assertEq(token.allowance(owner, spender), amount);
    }

    function _spend(address owner, address spender, address recipient, uint256 amount) private {
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, recipient, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[recipient] += amount;
        if (expectedAllowance[owner][spender] != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
        assertEq(token.balanceOf(owner), expectedBalance[owner]);
        assertEq(token.balanceOf(recipient), expectedBalance[recipient]);
        assertEq(token.allowance(owner, spender), expectedAllowance[owner][spender]);
        if (amount > 0) ++positiveDelegatedTransfers;
    }

    function _fundedActor(uint256 seed) private view returns (address) {
        uint256 start = seed % actors.length;
        for (uint256 i; i < actors.length; ++i) {
            address candidate = actors[(start + i) % actors.length];
            if (expectedBalance[candidate] > 0) return candidate;
        }
        // All supply remains among the actors. Never silently skip an unfunded action.
        revert("handler lost the entire supply");
    }

    function _otherActor(address from, uint256 seed) private view returns (address) {
        uint256 index = seed % actors.length;
        if (actors[index] == from) index = (index + 1) % actors.length;
        return actors[index];
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
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
        bytes4[] memory selectors = new bytes4[](13);
        selectors[0] = LARPHandler.move.selector;
        selectors[1] = LARPHandler.approve.selector;
        selectors[2] = LARPHandler.spend.selector;
        selectors[3] = LARPHandler.rejectedOverspend.selector;
        selectors[4] = LARPHandler.approveBoundary.selector;
        selectors[5] = LARPHandler.approveAndSpend.selector;
        selectors[6] = LARPHandler.moveAll.selector;
        selectors[7] = LARPHandler.roundTrip.selector;
        selectors[8] = LARPHandler.rejectedUnapprovedSpend.selector;
        selectors[9] = LARPHandler.rejectedDelegatedOverspend.selector;
        selectors[10] = LARPHandler.rejectedZeroRecipient.selector;
        selectors[11] = LARPHandler.rejectedZeroSpender.selector;
        selectors[12] = LARPHandler.revokeAndReject.selector;
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
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
    }

    function invariant_AllAllowancesMatchLedger() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(token.allowance(actors[i], actors[j]), handler.expectedAllowance(actors[i], actors[j]));
            }
        }
    }

    /// @dev After every campaign, every holder can still transfer its entire balance.
    function afterInvariant() public {
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.move(i, 0, handler.expectedBalance(actors[i]));
            assertEq(token.balanceOf(actors[i]), 0);
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY);
        handler.move(0, 1, SUPPLY);
        assertEq(token.balanceOf(actors[0]), 0);
        assertEq(token.balanceOf(actors[1]), SUPPLY);
        handler.move(1, 0, SUPPLY);
        assertEq(token.balanceOf(actors[0]), SUPPLY);
        invariant_SupplyAndAllBalancesMatchLedger();
        invariant_AllAllowancesMatchLedger();
    }

    /// @dev Pin a nonzero path through every selector; random call counts alone cannot show this.
    function test_HandlerExercisesTransfersApprovalsAndRejections() public {
        handler.move(0, 1, 100);
        handler.approve(1, 2, 50);
        handler.spend(1, 2, 3, 25);
        assertEq(token.balanceOf(actors[3]), 25);
        assertEq(token.allowance(actors[1], actors[2]), 25);
        invariant_SupplyAndAllBalancesMatchLedger();
        invariant_AllAllowancesMatchLedger();

        handler.approveBoundary(0, 1, 4);
        handler.spend(0, 1, 2, 1);
        assertEq(token.allowance(actors[0], actors[1]), type(uint256).max);
        handler.approveBoundary(0, 1, 3);
        handler.spend(0, 1, 2, 1);
        assertEq(token.allowance(actors[0], actors[1]), type(uint256).max - 2);
        handler.approveAndSpend(0, 2, 1, 1, false);
        handler.approveAndSpend(0, 2, 1, 1, true);
        handler.roundTrip(0, 1, 1);
        handler.moveAll(3, 2);
        handler.rejectedOverspend(1, 2);
        handler.rejectedUnapprovedSpend(0, 1, 2, 0);
        handler.rejectedDelegatedOverspend(0, 1, 2, false);
        handler.rejectedDelegatedOverspend(0, 1, 2, true);
        handler.rejectedZeroRecipient(0, 1, 1, false, false);
        handler.rejectedZeroRecipient(0, 1, 1, true, false);
        handler.rejectedZeroRecipient(0, 1, 0, true, true);
        handler.rejectedZeroSpender(0, 0);
        handler.revokeAndReject(0, 1, 2);

        assertGt(handler.positiveTransfers(), 0);
        assertGt(handler.positiveDelegatedTransfers(), 0);
        assertEq(handler.rejectedCalls(), 9);
        invariant_SupplyAndAllBalancesMatchLedger();
        invariant_AllAllowancesMatchLedger();
        afterInvariant();
    }
}
