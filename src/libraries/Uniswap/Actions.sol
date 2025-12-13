// SPDX-License-Identifier: MIT
pragma solidity >=0.8.18;

/// @title Actions
/// @notice Action constants for V4 Router operations
/// @dev Based on https://github.com/Uniswap/v4-periphery/blob/main/src/libraries/Actions.sol
library Actions {
    // Liquidity actions
    uint256 constant INCREASE_LIQUIDITY = 0x00;
    uint256 constant DECREASE_LIQUIDITY = 0x01;
    uint256 constant MINT_POSITION = 0x02;
    uint256 constant BURN_POSITION = 0x03;
    uint256 constant INCREASE_LIQUIDITY_FROM_DELTAS = 0x04;
    uint256 constant MINT_POSITION_FROM_DELTAS = 0x05;

    // Swapping
    uint256 constant SWAP_EXACT_IN_SINGLE = 0x06;
    uint256 constant SWAP_EXACT_IN = 0x07;
    uint256 constant SWAP_EXACT_OUT_SINGLE = 0x08;
    uint256 constant SWAP_EXACT_OUT = 0x09;

    // Donations
    uint256 constant DONATE = 0x0a;

    // Settlement
    uint256 constant SETTLE = 0x0b;
    uint256 constant SETTLE_ALL = 0x0c;
    uint256 constant SETTLE_PAIR = 0x0d;

    // Taking
    uint256 constant TAKE = 0x0e;
    uint256 constant TAKE_ALL = 0x0f;
    uint256 constant TAKE_PORTION = 0x10;
    uint256 constant TAKE_PAIR = 0x11;

    // Currency management
    uint256 constant CLOSE_CURRENCY = 0x12;
    uint256 constant CLEAR_OR_TAKE = 0x13;
    uint256 constant SWEEP = 0x14;

    // Wrapping
    uint256 constant WRAP = 0x15;
    uint256 constant UNWRAP = 0x16;

    // ERC6909 operations (unsupported in router/manager)
    uint256 constant MINT_6909 = 0x17;
    uint256 constant BURN_6909 = 0x18;
}
