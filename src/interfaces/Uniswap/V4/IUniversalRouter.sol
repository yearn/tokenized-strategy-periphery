// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.18;

/// @title IUniversalRouter
/// @notice Interface for Uniswap's Universal Router
interface IUniversalRouter {
    /// @notice Executes encoded commands along with provided inputs
    /// @param commands A set of concatenated commands, each 1 byte in length
    /// @param inputs An array of byte strings containing abi encoded inputs for each command
    /// @param deadline The deadline by which the transaction must be executed
    function execute(
        bytes calldata commands,
        bytes[] calldata inputs,
        uint256 deadline
    ) external payable;
}
