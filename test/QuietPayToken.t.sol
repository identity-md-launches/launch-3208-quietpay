// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {QuietPayToken} from "../src/QuietPayToken.sol";

/// @notice Deploys the token from a contract, so the test can check that the supply goes to
/// whichever address creates it (the IMD factory on the launch) and not to anyone else.
contract Deployer {
    function deploy() external returns (QuietPayToken token) {
        token = new QuietPayToken();
    }
}

contract QuietPayTokenTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 ether;
    uint256 internal constant SWARM_BPS = 1_000;

    QuietPayToken internal token;
    Deployer internal deployer;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);
    address internal constant ATTACKER = address(0xBEEF);

    function setUp() public {
        deployer = new Deployer();
        token = deployer.deploy();
    }

    // ----------------------------------------------------------------- metadata and supply

    function test_metadata() public view {
        assertEq(token.name(), "QuietPay");
        assertEq(token.symbol(), "QUIETPAY");
        assertEq(token.decimals(), 18);
        assertEq(token.TOKEN_NAME(), "QuietPay");
        assertEq(token.TOKEN_SYMBOL(), "QUIETPAY");
        assertEq(token.DECIMALS(), 18);
    }

    function test_totalSupplyIsOneBillionWithEighteenDecimals() public view {
        assertEq(token.TOTAL_SUPPLY(), EXPECTED_SUPPLY);
        assertEq(token.TOTAL_SUPPLY(), 1_000_000_000 * 10 ** 18);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_wholeSupplyIsMintedToTheDeployer() public view {
        assertEq(token.balanceOf(address(deployer)), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(address(this)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(0)), 0);
    }

    function test_constructorEmitsASingleMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), address(this), EXPECTED_SUPPLY);
        QuietPayToken fresh = new QuietPayToken();
        assertEq(fresh.balanceOf(address(this)), EXPECTED_SUPPLY);
        assertEq(fresh.totalSupply(), EXPECTED_SUPPLY);
    }

    /// @dev Whoever creates the contract receives the supply: the factory on the launch, no one
    /// baked in. Two deployments are independent tokens with independent supplies.
    function testFuzz_supplyGoesToWhoeverDeploys(address creator) public {
        vm.assume(creator != address(0) && creator.code.length == 0);
        vm.assume(uint160(creator) > 0xFFFF); // skip precompile range
        vm.prank(creator);
        QuietPayToken fresh = new QuietPayToken();
        assertEq(fresh.balanceOf(creator), EXPECTED_SUPPLY);
        assertEq(fresh.totalSupply(), EXPECTED_SUPPLY);
        // The first token is untouched.
        assertEq(token.balanceOf(creator), 0);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    // ----------------------------------------------------------------- transfer

    function test_transferMovesBalanceAndEmits() public {
        uint256 amount = 1_234 ether;
        vm.prank(address(deployer));
        token.transfer(ALICE, amount);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(ALICE, BOB, 500 ether);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 500 ether));

        assertEq(token.balanceOf(ALICE), amount - 500 ether);
        assertEq(token.balanceOf(BOB), 500 ether);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_transferOfZeroSucceeds() public {
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, 0));
        assertEq(token.balanceOf(BOB), 0);
    }

    function test_transferToSelfKeepsBalance() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 10 ether);
        vm.prank(ALICE);
        token.transfer(ALICE, 10 ether);
        assertEq(token.balanceOf(ALICE), 10 ether);
    }

    function test_transferRevertsOnInsufficientBalance() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 1 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 1 ether, 1 ether + 1)
        );
        vm.prank(ALICE);
        token.transfer(BOB, 1 ether + 1);
    }

    function test_transferRevertsWhenSenderHoldsNothing() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ATTACKER, 0, 1));
        vm.prank(ATTACKER);
        token.transfer(BOB, 1);
    }

    function test_transferToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(address(deployer));
        token.transfer(address(0), 1);
    }

    /// @dev No fee, no burn, no rounding: every ordinary transfer arrives exactly and conserves
    /// the total supply.
    function testFuzz_transferIsExactAndConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != address(deployer));
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        vm.prank(address(deployer));
        assertTrue(token.transfer(to, amount));
        assertEq(token.balanceOf(to), amount);
        assertEq(token.balanceOf(address(deployer)), EXPECTED_SUPPLY - amount);
        assertEq(token.balanceOf(to) + token.balanceOf(address(deployer)), EXPECTED_SUPPLY);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function testFuzz_transferAboveBalanceReverts(uint256 held, uint256 excess) public {
        held = bound(held, 0, EXPECTED_SUPPLY - 1);
        excess = bound(excess, 1, EXPECTED_SUPPLY - held);
        vm.prank(address(deployer));
        token.transfer(ALICE, held);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, held, held + excess)
        );
        vm.prank(ALICE);
        token.transfer(BOB, held + excess);
    }

    // ----------------------------------------------------------------- approve / transferFrom

    function test_approveSetsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Approval(ALICE, BOB, 7 ether);
        vm.prank(ALICE);
        assertTrue(token.approve(BOB, 7 ether));
        assertEq(token.allowance(ALICE, BOB), 7 ether);

        // A later approve overwrites rather than adds.
        vm.prank(ALICE);
        token.approve(BOB, 2 ether);
        assertEq(token.allowance(ALICE, BOB), 2 ether);
    }

    function test_approveToZeroAddressReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)));
        vm.prank(ALICE);
        token.approve(address(0), 1);
    }

    function test_transferFromSpendsAllowance() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(BOB, 60 ether);

        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(ALICE, CAROL, 40 ether);
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, CAROL, 40 ether));

        assertEq(token.balanceOf(ALICE), 60 ether);
        assertEq(token.balanceOf(CAROL), 40 ether);
        assertEq(token.balanceOf(BOB), 0);
        assertEq(token.allowance(ALICE, BOB), 20 ether);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    function test_transferFromWithMaxAllowanceDoesNotDecrement() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(BOB, type(uint256).max);
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 100 ether);
        assertEq(token.allowance(ALICE, BOB), type(uint256).max);
        assertEq(token.balanceOf(CAROL), 100 ether);
    }

    function test_transferFromRevertsOnInsufficientAllowance() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 100 ether);
        vm.prank(ALICE);
        token.approve(BOB, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 10 ether, 11 ether)
        );
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 11 ether);
    }

    function test_transferFromWithoutAnyAllowanceReverts() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 100 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, ATTACKER, 0, 1));
        vm.prank(ATTACKER);
        token.transferFrom(ALICE, ATTACKER, 1);
        assertEq(token.balanceOf(ALICE), 100 ether);
    }

    function test_transferFromRevertsWhenAllowanceExceedsBalance() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, 5 ether);
        vm.prank(ALICE);
        token.approve(BOB, 10 ether);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, ALICE, 5 ether, 6 ether));
        vm.prank(BOB);
        token.transferFrom(ALICE, CAROL, 6 ether);
    }

    function testFuzz_transferFromIsExactWithinAllowance(uint256 held, uint256 allowed, uint256 spent) public {
        held = bound(held, 0, EXPECTED_SUPPLY);
        allowed = bound(allowed, 0, held);
        spent = bound(spent, 0, allowed);
        vm.prank(address(deployer));
        token.transfer(ALICE, held);
        vm.prank(ALICE);
        token.approve(BOB, allowed);
        vm.prank(BOB);
        assertTrue(token.transferFrom(ALICE, CAROL, spent));
        assertEq(token.balanceOf(CAROL), spent);
        assertEq(token.balanceOf(ALICE), held - spent);
        assertEq(token.allowance(ALICE, BOB), allowed - spent);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    // ----------------------------------------------------------------- launch flows

    /// @dev The flows the launch performs: the swarm's ten percent leaves the factory whole and is
    /// forwarded whole by the distributor; the rest moves whole to the pool and the requester.
    function test_launchFlowsArriveWhole() public {
        address distributor = address(0xD157);
        address claimant = address(0xC1A1);
        address pool = address(0x9001);
        address requester = address(0x612a9bB008e16ef2D24f41DAe9Fc661831d93367);

        uint256 swarm = (EXPECTED_SUPPLY * SWARM_BPS) / 10_000;
        uint256 poolShare = (EXPECTED_SUPPLY * 8_000) / 10_000;
        uint256 remainder = EXPECTED_SUPPLY - swarm - poolShare;

        vm.startPrank(address(deployer));
        assertTrue(token.transfer(distributor, swarm));
        assertTrue(token.transfer(pool, poolShare));
        assertTrue(token.transfer(requester, remainder));
        vm.stopPrank();

        assertEq(token.balanceOf(distributor), swarm);
        assertEq(token.balanceOf(pool), poolShare);
        assertEq(token.balanceOf(requester), remainder);
        assertEq(token.balanceOf(address(deployer)), 0);

        vm.prank(distributor);
        assertTrue(token.transfer(claimant, swarm));
        assertEq(token.balanceOf(claimant), swarm);
        assertEq(token.balanceOf(distributor), 0);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
    }

    // ----------------------------------------------------------------- no privileged surface

    /// @dev The supply can never grow. None of the usual admin entry points exist; each call
    /// reverts and leaves the supply and the caller's balance as they were, from a stranger and
    /// from the deployer alike.
    function test_noCallIncreasesSupply() public {
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ATTACKER, type(uint128).max);
            vm.prank(ATTACKER);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            vm.prank(address(deployer));
            (ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            assertEq(token.totalSupply(), EXPECTED_SUPPLY, signatures[i]);
            assertEq(token.balanceOf(ATTACKER), 0, signatures[i]);
        }
    }

    /// @dev Nobody but a holder moves or freezes the holder's balance. Every privileged call in the
    /// list is tried from the deployer, the address a token would most plausibly trust.
    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        vm.prank(address(deployer));
        token.transfer(ALICE, EXPECTED_SUPPLY / 1_000);
        uint256 held = token.balanceOf(ALICE);

        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            vm.prank(address(deployer));
            (bool ok,) = address(token).call(abi.encodeWithSignature(signatures[i], ALICE, true));
            assertFalse(ok, signatures[i]);
        }
        vm.prank(address(deployer));
        (bool moved,) = address(token).call(abi.encodeWithSelector(IERC20.transferFrom.selector, ALICE, deployer, 1));
        assertFalse(moved, "transferFrom without allowance must revert");

        assertEq(token.balanceOf(ALICE), held);
        vm.prank(ALICE);
        assertTrue(token.transfer(BOB, held / 2));
        assertEq(token.balanceOf(BOB), held / 2);
    }

    function test_hasNoOwner() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("owner()"));
        assertFalse(ok, "the token must not expose an owner");
    }

    function test_rejectsEther() public {
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        (bool ok,) = address(token).call{value: 1 ether}("");
        assertFalse(ok, "the token must not accept ether");
        assertEq(address(token).balance, 0);
    }

    /// @dev Reachable runtime code contains no DELEGATECALL, CALLCODE or SELFDESTRUCT, scanned the
    /// way the launch floor scans it: PUSH data is skipped, and bytes after a terminating opcode
    /// are data until the next JUMPDEST.
    function test_runtimeCodeHasNoDelegatecallOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576, "runtime exceeds EIP-170");
        bool reachable = true;
        for (uint256 i = 0; i < runtime.length; i++) {
            uint8 op = uint8(runtime[i]);
            if (op == 0x5B) reachable = true;
            if (op >= 0x60 && op <= 0x7F) {
                i += (op - 0x5F);
                continue;
            }
            if (reachable) {
                assertTrue(op != 0xF4, "runtime code contains DELEGATECALL");
                assertTrue(op != 0xF2, "runtime code contains CALLCODE");
                assertTrue(op != 0xFF, "runtime code contains SELFDESTRUCT");
            }
            if (op == 0x00 || op == 0x56 || op == 0xF3 || op == 0xFD || op == 0xFE || op == 0xFF) reachable = false;
        }
    }
}
