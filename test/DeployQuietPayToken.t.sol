// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {QuietPayToken} from "../src/QuietPayToken.sol";
import {DeployQuietPayToken} from "../script/DeployQuietPayToken.s.sol";

/// @notice The deploy script's `deploy()` is called directly, with no environment and no
/// broadcast, so the test passes in any order and in parallel.
contract DeployQuietPayTokenTest is Test {
    function test_deployMintsTheSupplyToTheScriptCaller() public {
        DeployQuietPayToken script = new DeployQuietPayToken();
        QuietPayToken token = script.deploy();
        assertEq(token.name(), "QuietPay");
        assertEq(token.symbol(), "QUIETPAY");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), 1_000_000_000 ether);
        // `new` inside the script makes the script contract the deployer, so it holds the supply.
        assertEq(token.balanceOf(address(script)), 1_000_000_000 ether);
    }
}
