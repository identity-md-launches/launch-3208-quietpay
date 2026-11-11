// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title QuietPay (QUIETPAY)
/// @notice A fixed-supply ERC-20. The whole supply is minted once, to the deployer, in the
/// constructor. There is no owner, no minter, no pause, no blocklist and no fee: after
/// deployment the contract has no privileged functions at all, and the supply can never grow.
/// @dev The contract name is the launch's identifier for this token (at most 32 characters);
/// the token's own name and symbol are what `name()` and `symbol()` return. The constructor
/// takes no arguments and calls no other contract, so it deploys on an empty chain.
contract QuietPayToken is ERC20 {
    /// @notice The token name returned by `name()`.
    string public constant TOKEN_NAME = "QuietPay";

    /// @notice The token symbol returned by `symbol()`.
    string public constant TOKEN_SYMBOL = "QUIETPAY";

    /// @notice The number of decimals, as `decimals()` returns it.
    uint8 public constant DECIMALS = 18;

    /// @notice The total supply in minor units: 1,000,000,000 tokens with 18 decimals.
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10 ** uint256(DECIMALS);

    /// @notice Mints the whole fixed supply to the deployer, once.
    /// @dev `msg.sender` is the address that creates the contract. On the IMD launch that is the
    /// factory, which then pays the supply out; nothing is reserved for any other address here.
    constructor() ERC20(TOKEN_NAME, TOKEN_SYMBOL) {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
