// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

/**
 * @title BaseSwapper
 * @author yearn.fi
 * @dev Base contract for all swapper contracts except TradeFactorySwapper.
 *      Contains the common minAmountToSell variable that most swappers need.
 */
contract BaseSwapper {
    /// @notice Minimum amount of tokens to sell in a swap.
    uint256 public minAmountToSell;
}
