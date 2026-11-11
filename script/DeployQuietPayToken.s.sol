// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script} from "forge-std/Script.sol";
import {QuietPayToken} from "../src/QuietPayToken.sol";

/// @title DeployQuietPayToken
/// @notice Reviewable deployment script for QuietPayToken. The token takes no constructor
/// arguments, so there is no configuration to read: `deploy()` is the whole deployment and the
/// tests call it directly. `run()` only wraps it in a broadcast for a manual deployment.
/// @dev On the IMD launch this script is not used: the factory deploys the token from its
/// bytecode and receives the supply as `msg.sender`. Whoever calls `deploy()` here receives it.
contract DeployQuietPayToken is Script {
    /// @notice Deploys the token. The caller receives the whole supply.
    function deploy() public returns (QuietPayToken token) {
        token = new QuietPayToken();
    }

    /// @notice Broadcast entry point for a manual deployment with `forge script --broadcast`.
    function run() external returns (QuietPayToken token) {
        vm.startBroadcast();
        token = deploy();
        vm.stopBroadcast();
    }
}
