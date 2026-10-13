// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/IERC6093.sol";
import {LARPToken} from "../src/LARPToken.sol";

/// @dev Test-only factory: the controller represents the launch service, not a token administrator.
contract TokenFactoryHarness {
    address private immutable controller = msg.sender;
    LARPToken public immutable token;

    constructor() {
        token = new LARPToken();
    }

    function distribute(address to, uint256 amount) external {
        require(msg.sender == controller, "only test controller");
        require(token.transfer(to, amount), "transfer failed");
    }
}

/// @dev A recipient whose fallback rejects callbacks; ERC-20 transfers must not invoke it.
contract RejectingRecipient {
    fallback() external {
        revert("unexpected callback");
    }
}

contract LARPTokenTest is Test {
    uint256 private constant SUPPLY = 1_000_000_000_000_000_000_000_000_000;

    LARPToken private token;
    address private alice = makeAddr("alice");
    address private bob = makeAddr("bob");
    address private spender = makeAddr("spender");

    function setUp() public {
        token = new LARPToken();
    }

    function test_MetadataAndInitialSupply() public view {
        assertEq(token.name(), "Linked Avatar Registry Protocol");
        assertEq(token.symbol(), "LARP");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_ConstructorEmitsExactlyOneMint() public {
        vm.recordLogs();
        LARPToken deployed = new LARPToken();
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 1);
        assertEq(entries[0].emitter, address(deployed));
        assertEq(entries[0].topics.length, 3);
        assertEq(entries[0].topics[0], keccak256("Transfer(address,address,uint256)"));
        assertEq(entries[0].topics[1], bytes32(0));
        assertEq(entries[0].topics[2], bytes32(uint256(uint160(address(this)))));
        assertEq(abi.decode(entries[0].data, (uint256)), SUPPLY);
    }

    function test_FactoryReceivesWholeSupply() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        LARPToken deployed = factory.token();
        assertEq(deployed.balanceOf(address(factory)), SUPPLY);
        assertEq(deployed.balanceOf(address(this)), 0);
        assertEq(deployed.balanceOf(address(deployed)), 0);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_LaunchDistributionClaimsAndTradingTransfersArriveWhole() public {
        TokenFactoryHarness factory = new TokenFactoryHarness();
        LARPToken deployed = factory.token();
        address distributor = makeAddr("distributor");
        address poolManager = makeAddr("poolManager");
        address requester = makeAddr("requester");
        uint256 swarm = SUPPLY / 10;
        uint256 pool = SUPPLY * 8 / 10;
        factory.distribute(distributor, swarm);
        factory.distribute(poolManager, pool);
        factory.distribute(requester, SUPPLY - swarm - pool);
        assertEq(deployed.balanceOf(address(factory)), 0);
        assertEq(deployed.balanceOf(distributor), swarm);
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.balanceOf(requester), SUPPLY / 10);

        vm.prank(distributor);
        assertTrue(deployed.transfer(alice, swarm));
        assertEq(deployed.balanceOf(distributor), 0);
        assertEq(deployed.balanceOf(alice), swarm);

        uint256 bought = 123 ether;
        vm.prank(poolManager);
        assertTrue(deployed.transfer(bob, bought));
        assertEq(deployed.balanceOf(bob), bought);
        vm.prank(bob);
        assertTrue(deployed.transfer(poolManager, bought));
        assertEq(deployed.balanceOf(bob), 0);
        assertEq(deployed.balanceOf(poolManager), pool);
        assertEq(deployed.totalSupply(), SUPPLY);
    }

    function test_TransferEmitsEventAndArrivesWhole() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 75 ether);
        assertTrue(token.transfer(alice, 75 ether));
        assertEq(token.balanceOf(alice), 75 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 75 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_EntireSupplyCanMove() public {
        assertTrue(token.transfer(alice, SUPPLY));
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        vm.prank(alice);
        assertTrue(token.transfer(bob, SUPPLY));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferFromEmptyAccountEmitsEvent() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(alice, bob, 0);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_SelfTransferPreservesBalance() public {
        assertTrue(token.transfer(address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferDoesNotCallRecipient() public {
        RejectingRecipient recipient = new RejectingRecipient();
        assertTrue(token.transfer(address(recipient), 1 ether));
        assertEq(token.balanceOf(address(recipient)), 1 ether);
    }

    function test_TransferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_ZeroTransferToZeroReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    function test_TransferFromEmptyBalanceReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        vm.prank(alice);
        token.transfer(bob, 1);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_MaximumTransferRevertsWithoutOverflow() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
            )
        );
        token.transfer(alice, type(uint256).max);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_ApproveEmitsEventAndDoesNotMoveFunds() public {
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 42 ether);
        assertTrue(token.approve(spender, 42 ether));
        assertEq(token.allowance(address(this), spender), 42 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(spender), 0);
    }

    function test_ApproveOverwritesAndCanBeRevoked() public {
        token.approve(spender, 42 ether);
        token.approve(spender, 10 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        token.approve(spender, 0);
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
    }

    function test_ApproveZeroSpenderReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
        assertEq(token.allowance(address(this), address(0)), 0);
    }

    function test_TransferFromEmitsAndConsumesFiniteAllowance() public {
        token.approve(spender, 50 ether);
        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Transfer(address(this), alice, 30 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 30 ether));
        assertEq(token.allowance(address(this), spender), 20 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY - 30 ether);
        assertEq(token.balanceOf(alice), 30 ether);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromExactAllowanceThenFurtherSpendReverts() public {
        token.approve(spender, 50 ether);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 50 ether));
        assertEq(token.allowance(address(this), spender), 0);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1));
        vm.prank(spender);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.balanceOf(alice), 50 ether);
    }

    function test_InfiniteAllowanceIsNotReduced() public {
        token.approve(spender, type(uint256).max);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, SUPPLY));
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        assertEq(token.balanceOf(alice), SUPPLY);
    }

    function test_TransferFromSelfStillConsumesAllowance() public {
        token.approve(spender, SUPPLY);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), address(this), SUPPLY));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.allowance(address(this), spender), 0);
    }

    function test_OwnerUsingTransferFromNeedsAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(address(this), alice, 1);
    }

    function test_ZeroTransferFromWithoutApprovalSucceeds() public {
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 0));
        assertEq(token.allowance(alice, spender), 0);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_ApprovalDoesNotAuthorizeAnotherSpender() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        vm.prank(bob);
        token.transferFrom(address(this), alice, 1);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_TransferFromInsufficientBalanceRollsBackAllowance() public {
        vm.prank(alice);
        token.approve(spender, 20 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 10 ether));
        vm.prank(spender);
        token.transferFrom(alice, bob, 10 ether);
        assertEq(token.allowance(alice, spender), 20 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    function test_TransferFromZeroRecipientRollsBackAllowance() public {
        token.approve(spender, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(this), address(0), 10 ether);
        assertEq(token.allowance(address(this), spender), 10 ether);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_TransferFromZeroSenderReverts() public {
        // A zero-value call passes the allowance check, then rejects the zero sender.
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        vm.prank(spender);
        token.transferFrom(address(0), alice, 0);
    }

    function test_NoAdministrativeOrExtraMintingSurface() public {
        token.transfer(alice, 100 ether);
        bytes[] memory attempts = new bytes[](15);
        attempts[0] = abi.encodeWithSignature("mint(address,uint256)", bob, 1 ether);
        attempts[1] = abi.encodeWithSignature("mint(uint256)", 1 ether);
        attempts[2] = abi.encodeWithSignature("mint()");
        attempts[3] = abi.encodeWithSignature("initialize(address)", bob);
        attempts[4] = abi.encodeWithSignature("setMinter(address)", bob);
        attempts[5] = abi.encodeWithSignature("transferOwnership(address)", bob);
        attempts[6] = abi.encodeWithSignature("upgradeTo(address)", bob);
        attempts[7] = abi.encodeWithSignature("pause()");
        attempts[8] = abi.encodeWithSignature("blacklist(address)", alice);
        attempts[9] = abi.encodeWithSignature("freeze(address)", alice);
        attempts[10] = abi.encodeWithSignature("burnFrom(address,uint256)", alice, 1 ether);
        attempts[11] = abi.encodeWithSignature("burn(uint256)", 1 ether);
        attempts[12] = abi.encodeWithSignature("seize(address)", alice);
        attempts[13] = abi.encodeWithSignature("setTransfersEnabled(bool)", false);
        attempts[14] = abi.encodeWithSignature("setTax(uint256)", 100);
        for (uint256 i; i < attempts.length; ++i) {
            (bool deployerSucceeded,) = address(token).call(attempts[i]);
            assertFalse(deployerSucceeded);
            vm.prank(bob);
            (bool strangerSucceeded,) = address(token).call(attempts[i]);
            assertFalse(strangerSucceeded);
            assertEq(token.totalSupply(), SUPPLY);
            assertEq(token.balanceOf(alice), 100 ether);
            assertEq(token.balanceOf(bob), 0);
        }
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(alice, address(this), 1);
        vm.prank(alice);
        assertTrue(token.transfer(bob, 100 ether));
        assertEq(token.balanceOf(bob), 100 ether);
    }

    function test_RejectsEtherAndUnknownCalls() public {
        vm.deal(address(this), 1 ether);
        (bool plainEther,) = address(token).call{value: 1 wei}("");
        (bool unknown,) = address(token).call(hex"ffffffff");
        (bool payableTransfer,) = address(token).call{value: 1 wei}(abi.encodeCall(IERC20.transfer, (alice, 1)));
        assertFalse(plainEther);
        assertFalse(unknown);
        assertFalse(payableTransfer);
        assertEq(address(token).balance, 0);
        assertEq(token.balanceOf(address(this)), SUPPLY);
    }

    function test_RuntimeSizeAndNoForbiddenOpcodes() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        assertLe(type(LARPToken).creationCode.length, 49_152);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 opcode = uint8(runtime[i]);
            if (opcode >= 0x60 && opcode <= 0x7f) {
                i += opcode - 0x5f;
            } else {
                assertTrue(opcode != 0xf2 && opcode != 0xf4 && opcode != 0xff);
            }
        }
    }

    function testFuzz_DeploymentMintsOnlyToImmediateCaller(address deployer) public {
        vm.assume(deployer != address(0));
        vm.prank(deployer);
        LARPToken deployed = new LARPToken();
        assertEq(deployed.totalSupply(), SUPPLY);
        assertEq(deployed.balanceOf(deployer), SUPPLY);
        assertEq(deployed.balanceOf(address(0)), 0);
    }

    function testFuzz_TransferConservesSupply(address recipient, uint256 amount) public {
        vm.assume(recipient != address(0) && recipient != address(this));
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(recipient, amount));
        assertEq(token.balanceOf(recipient), amount);
        assertEq(token.balanceOf(address(this)), SUPPLY - amount);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_SelfTransferConservesBalance(uint256 amount) public {
        amount = bound(amount, 0, SUPPLY);
        assertTrue(token.transfer(address(this), amount));
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferAboveBalanceReverts(uint256 balance, uint256 extra) public {
        balance = bound(balance, 0, SUPPLY);
        extra = bound(extra, 1, type(uint256).max - balance);
        token.transfer(alice, balance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, balance, balance + extra)
        );
        vm.prank(alice);
        token.transfer(bob, balance + extra);
        assertEq(token.balanceOf(alice), balance);
        assertEq(token.balanceOf(bob), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromAccountsForAllowance(uint256 approved, uint256 spent) public {
        uint256 limit = approved < SUPPLY ? approved : SUPPLY;
        spent = bound(spent, 0, limit);
        token.approve(spender, approved);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, spent));
        assertEq(token.balanceOf(alice), spent);
        assertEq(token.balanceOf(address(this)), SUPPLY - spent);
        assertEq(token.allowance(address(this), spender), approved == type(uint256).max ? approved : approved - spent);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function testFuzz_TransferFromAboveAllowanceReverts(uint256 approved, uint256 excess) public {
        approved = bound(approved, 0, SUPPLY - 1);
        excess = bound(excess, 1, SUPPLY - approved);
        token.approve(spender, approved);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + excess
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, approved + excess);
        assertEq(token.allowance(address(this), spender), approved);
        assertEq(token.balanceOf(address(this)), SUPPLY);
        assertEq(token.balanceOf(alice), 0);
    }
}
