// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {QuietPayToken} from "../src/QuietPayToken.sol";

/// @notice Edge cases the main suite does not pin: boundary amounts, the zero address on every
/// side, owners spending their own tokens, allowance overwrites and the same call repeated.
contract QuietPayTokenEdgeTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 ether;

    QuietPayToken internal token;
    address internal holder = makeAddr("holder");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.prank(holder);
        token = new QuietPayToken();
    }

    // ------------------------------------------------------------------ boundary amounts

    function test_transferOfWholeSupply() public {
        vm.prank(holder);
        token.transfer(alice, SUPPLY);
        assertEq(token.balanceOf(holder), 0);
        assertEq(token.balanceOf(alice), SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
    }

    function test_transferOfWholeSupplyPlusOneWeiReverts() public {
        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, SUPPLY + 1)
        );
        token.transfer(alice, SUPPLY + 1);
    }

    function test_transferOfMaxUintReverts() public {
        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, holder, SUPPLY, type(uint256).max)
        );
        token.transfer(alice, type(uint256).max);
    }

    function test_oneWeiRoundTrip() public {
        vm.prank(holder);
        token.transfer(alice, 1);
        vm.prank(alice);
        token.transfer(holder, 1);
        assertEq(token.balanceOf(alice), 0);
        assertEq(token.balanceOf(holder), SUPPLY);
    }

    function test_emptyAccountCanSendZero() public {
        vm.prank(alice);
        assertTrue(token.transfer(bob, 0));
        assertEq(token.balanceOf(bob), 0);
    }

    function test_emptyAccountCannotSendOneWei() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_sameTransferTwiceFailsOnceBalanceIsSpent() public {
        vm.prank(holder);
        token.transfer(alice, 5 ether);
        vm.prank(alice);
        token.transfer(bob, 5 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 5 ether));
        token.transfer(bob, 5 ether);
        assertEq(token.balanceOf(bob), 5 ether);
    }

    // ------------------------------------------------------------------ zero address

    function test_transferFromToZeroAddressReverts() public {
        vm.prank(holder);
        token.approve(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transferFrom(holder, address(0), 1 ether);
        assertEq(token.allowance(holder, alice), 1 ether, "failed call spent allowance");
        assertEq(token.balanceOf(holder), SUPPLY);
    }

    function test_transferFromTheZeroAddressReverts() public {
        // Nobody can approve on behalf of address(0), so the allowance check fails first.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(address(0), bob, 1);
    }

    function test_zeroAddressCannotSend() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSender.selector, address(0)));
        token.transfer(alice, 0);
    }

    function test_zeroAddressCannotApprove() public {
        vm.prank(address(0));
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidApprover.selector, address(0)));
        token.approve(alice, 1);
    }

    function test_zeroAmountTransferToZeroAddressStillReverts() public {
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 0);
    }

    // ------------------------------------------------------------------ allowances

    function test_ownerNeedsAllowanceToUseTransferFromOnThemself() public {
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, holder, 0, 1));
        token.transferFrom(holder, alice, 1);
    }

    function test_approveOverwritesRatherThanAdds() public {
        vm.startPrank(holder);
        token.approve(alice, 10 ether);
        token.approve(alice, 3 ether);
        vm.stopPrank();
        assertEq(token.allowance(holder, alice), 3 ether);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 3 ether, 4 ether)
        );
        token.transferFrom(holder, bob, 4 ether);
    }

    function test_approveZeroRevokes() public {
        vm.startPrank(holder);
        token.approve(alice, 10 ether);
        token.approve(alice, 0);
        vm.stopPrank();
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(holder, bob, 1);
    }

    function test_allowanceSpentExactlyToZeroThenBlocks() public {
        vm.prank(holder);
        token.approve(alice, 2 ether);
        vm.startPrank(alice);
        token.transferFrom(holder, bob, 1 ether);
        token.transferFrom(holder, bob, 1 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(holder, bob, 1);
        vm.stopPrank();
        assertEq(token.allowance(holder, alice), 0);
        assertEq(token.balanceOf(bob), 2 ether);
    }

    function test_allowanceIsPerSpender() public {
        vm.prank(holder);
        token.approve(alice, 1 ether);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 1));
        token.transferFrom(holder, bob, 1);
    }

    function test_allowanceIsPerOwner() public {
        vm.prank(holder);
        token.transfer(bob, 5 ether);
        vm.prank(holder);
        token.approve(alice, 5 ether);
        // alice's allowance from holder does not let her move bob's tokens
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 0, 1));
        token.transferFrom(bob, alice, 1);
    }

    function test_transferFromDoesNotEmitApprovalOnSpend() public {
        vm.prank(holder);
        token.approve(alice, 2 ether);
        vm.recordLogs();
        vm.prank(alice);
        token.transferFrom(holder, bob, 1 ether);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1);
        assertEq(logs[0].topics[0], IERC20.Transfer.selector);
    }

    function test_unlimitedAllowanceSurvivesWholeSupplyMove() public {
        vm.prank(holder);
        token.approve(alice, type(uint256).max);
        vm.prank(alice);
        token.transferFrom(holder, bob, SUPPLY);
        assertEq(token.allowance(holder, alice), type(uint256).max);
        assertEq(token.balanceOf(bob), SUPPLY);
    }

    function test_maxMinusOneAllowanceIsDecremented() public {
        vm.prank(holder);
        token.approve(alice, type(uint256).max - 1);
        vm.prank(alice);
        token.transferFrom(holder, bob, 1);
        assertEq(token.allowance(holder, alice), type(uint256).max - 2);
    }

    // ------------------------------------------------------------------ fuzzed properties

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_transferFromSelfToSelfKeepsBalanceAndSpendsAllowance(uint256 allowed, uint256 amount) public {
        allowed = bound(allowed, 0, type(uint256).max - 1);
        amount = bound(amount, 0, allowed < SUPPLY ? allowed : SUPPLY);
        vm.prank(holder);
        token.approve(alice, allowed);
        vm.prank(alice);
        token.transferFrom(holder, holder, amount);
        assertEq(token.balanceOf(holder), SUPPLY);
        assertEq(token.allowance(holder, alice), allowed - amount);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_failedTransferChangesNothing(uint256 amount) public {
        vm.prank(holder);
        token.transfer(alice, 1 ether);
        amount = bound(amount, 1 ether + 1, type(uint256).max);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1 ether, amount));
        token.transfer(bob, amount);
        assertEq(token.balanceOf(alice), 1 ether);
        assertEq(token.balanceOf(bob), 0);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_splitTransfersEqualOneTransfer(uint256 a, uint256 b) public {
        a = bound(a, 0, SUPPLY);
        b = bound(b, 0, SUPPLY - a);
        vm.startPrank(holder);
        token.transfer(alice, a);
        token.transfer(alice, b);
        vm.stopPrank();
        assertEq(token.balanceOf(alice), a + b);
        assertEq(token.balanceOf(holder), SUPPLY - a - b);
    }

    /// forge-config: default.fuzz.runs = 1000
    function testFuzz_strangerCannotMoveAnything(address stranger, uint256 amount) public {
        vm.assume(stranger != holder && stranger != address(0));
        amount = bound(amount, 1, type(uint256).max);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount));
        token.transferFrom(holder, stranger, amount);
        assertEq(token.balanceOf(holder), SUPPLY);
    }
}
