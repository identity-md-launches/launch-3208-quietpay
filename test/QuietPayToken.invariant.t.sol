// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {QuietPayToken} from "../src/QuietPayToken.sol";

/// @notice Drives the token with bounded random calls from a fixed set of actors and keeps an
/// independent model (ghost balances and allowances) of what the token must hold after each call.
/// Calls that must fail are made too, and the handler asserts that they revert with the right
/// error and leave the state untouched.
contract QuietPayHandler is Test {
    QuietPayToken public immutable token;

    address[] internal actors;
    mapping(address => uint256) public ghostBalance;
    mapping(address => mapping(address => uint256)) public ghostAllowance;

    /// @dev Counts every call whose outcome disagreed with the model. Kept as a counter rather than
    /// a revert so that the invariant runner, which ignores handler reverts by default, sees it.
    uint256 public ghostViolations;
    uint256 public ghostTransfers;
    uint256 public ghostTransferFroms;
    uint256 public ghostExpectedReverts;
    uint256 public ghostVolume;

    constructor(QuietPayToken token_, address[] memory actors_) {
        token = token_;
        actors = actors_;
        for (uint256 i = 0; i < actors_.length; i++) {
            ghostBalance[actors_[i]] = token_.balanceOf(actors_[i]);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function actorAt(uint256 i) external view returns (address) {
        return actors[i];
    }

    function _actor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    // ------------------------------------------------------------------ succeeding calls

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        vm.prank(from);
        try token.transfer(to, amount) returns (bool ok) {
            if (!ok) ghostViolations++;
        } catch {
            ghostViolations++;
            return;
        }

        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostTransfers++;
        ghostVolume += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited) external {
        address owner = _actor(ownerSeed);
        address spender = _actor(spenderSeed);
        if (unlimited) amount = type(uint256).max;

        vm.prank(owner);
        try token.approve(spender, amount) returns (bool ok) {
            if (!ok) ghostViolations++;
        } catch {
            ghostViolations++;
            return;
        }

        ghostAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        uint256 cap = allowed < ghostBalance[from] ? allowed : ghostBalance[from];
        amount = bound(amount, 0, cap);

        vm.prank(spender);
        try token.transferFrom(from, to, amount) returns (bool ok) {
            if (!ok) ghostViolations++;
        } catch {
            ghostViolations++;
            return;
        }

        if (allowed != type(uint256).max) ghostAllowance[from][spender] = allowed - amount;
        ghostBalance[from] -= amount;
        ghostBalance[to] += amount;
        ghostTransferFroms++;
        ghostVolume += amount;
    }

    // ------------------------------------------------------------------ failing calls

    function transferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[from];
        excess = bound(excess, 1, type(uint256).max - held);
        uint256 amount = held + excess;

        vm.prank(from);
        try token.transfer(to, amount) {
            ghostViolations++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount)
                    )
            ) ghostViolations++;
        }
        ghostExpectedReverts++;
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        amount = bound(amount, 0, ghostBalance[from]);

        vm.prank(from);
        try token.transfer(address(0), amount) {
            ghostViolations++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)))
            ) ghostViolations++;
        }
        ghostExpectedReverts++;
    }

    function transferFromAboveAllowance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess)
        external
    {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 allowed = ghostAllowance[from][spender];
        if (allowed == type(uint256).max) return; // an unlimited allowance cannot be exceeded
        excess = bound(excess, 1, type(uint256).max - allowed);
        uint256 amount = allowed + excess;

        vm.prank(spender);
        try token.transferFrom(from, to, amount) {
            ghostViolations++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(
                            IERC20Errors.ERC20InsufficientAllowance.selector, spender, allowed, amount
                        )
                    )
            ) ghostViolations++;
        }
        ghostExpectedReverts++;
    }

    function transferFromAboveBalance(uint256 spenderSeed, uint256 fromSeed, uint256 toSeed, uint256 excess) external {
        address spender = _actor(spenderSeed);
        address from = _actor(fromSeed);
        address to = _actor(toSeed);
        uint256 held = ghostBalance[from];
        excess = bound(excess, 1, type(uint256).max - held);
        uint256 amount = held + excess;

        // Give the spender enough allowance so that only the balance check can fail.
        vm.prank(from);
        token.approve(spender, type(uint256).max);
        ghostAllowance[from][spender] = type(uint256).max;

        vm.prank(spender);
        try token.transferFrom(from, to, amount) {
            ghostViolations++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, from, held, amount)
                    )
            ) ghostViolations++;
        }
        ghostExpectedReverts++;
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = _actor(ownerSeed);
        vm.prank(owner);
        try token.approve(address(0), amount) {
            ghostViolations++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0)))
            ) ghostViolations++;
        }
        ghostExpectedReverts++;
    }

    /// @dev A stranger outside the actor set holds nothing and was approved by nobody, so it can
    /// move nothing from anyone.
    function strangerTransferFrom(address stranger, uint256 fromSeed, uint256 amount) external {
        address from = _actor(fromSeed);
        if (ghostAllowance[from][stranger] != 0 || stranger == address(0)) return;
        for (uint256 i = 0; i < actors.length; i++) {
            if (actors[i] == stranger) return;
        }
        amount = bound(amount, 1, type(uint256).max);

        vm.prank(stranger);
        try token.transferFrom(from, stranger, amount) {
            ghostViolations++;
        } catch (bytes memory reason) {
            if (
                keccak256(reason)
                    != keccak256(
                        abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, stranger, 0, amount)
                    )
            ) ghostViolations++;
        }
        ghostExpectedReverts++;
    }
}

contract QuietPayTokenInvariantTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 ether;

    QuietPayToken internal token;
    QuietPayHandler internal handler;
    address[] internal actors;

    function setUp() public {
        address deployer = makeAddr("deployer");
        vm.prank(deployer);
        token = new QuietPayToken();

        actors.push(deployer);
        actors.push(makeAddr("alice"));
        actors.push(makeAddr("bob"));
        actors.push(makeAddr("carol"));
        actors.push(makeAddr("dave"));

        // Spread the supply a little so every actor starts with something to move.
        vm.startPrank(deployer);
        token.transfer(actors[1], 100_000_000 ether);
        token.transfer(actors[2], 10_000_000 ether);
        token.transfer(actors[3], 1 ether);
        token.transfer(actors[4], 1);
        vm.stopPrank();

        handler = new QuietPayHandler(token, actors);
        targetContract(address(handler));
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_totalSupplyIsFixed() public view {
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.totalSupply(), token.TOTAL_SUPPLY());
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesSumToSupply() public view {
        uint256 sum;
        for (uint256 i = 0; i < actors.length; i++) {
            sum += token.balanceOf(actors[i]);
        }
        assertEq(sum, token.totalSupply(), "tokens appeared or vanished outside the actor set");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_balancesMatchModel() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            assertEq(token.balanceOf(actors[i]), handler.ghostBalance(actors[i]), "balance drifted from model");
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_allowancesMatchModel() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            for (uint256 j = 0; j < actors.length; j++) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.ghostAllowance(actors[i], actors[j]),
                    "allowance drifted from model"
                );
            }
        }
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_nothingLeaksToZeroOrTheToken() public view {
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(address(token).balance, 0);
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_everyCallMatchedTheModel() public view {
        assertEq(handler.ghostViolations(), 0, "a call succeeded, failed or reverted unlike the model");
    }

    /// forge-config: default.invariant.runs = 256
    /// forge-config: default.invariant.depth = 64
    function invariant_noBalanceExceedsSupply() public view {
        for (uint256 i = 0; i < actors.length; i++) {
            assertLe(token.balanceOf(actors[i]), EXPECTED_SUPPLY);
        }
    }
}
