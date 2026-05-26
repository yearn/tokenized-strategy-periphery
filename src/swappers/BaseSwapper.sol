// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

/**
 * @title BaseSwapper
 * @author yearn.fi
 * @dev Base contract for all swapper contracts except TradeFactorySwapper.
 *      Contains the common minAmountToSell mapping that most swappers need.
 */
contract BaseSwapper {
    /// @notice Minimum amount of tokens to sell in a swap.
    mapping(address => uint256) public minAmountToSell;

    /**
     * @dev Set the minimum amount to sell in a swap.
     * @param _token Token to set the minimum for.
     * @param _minAmountToSell Minimum amount of tokens needed to execute a swap.
     */
    function _setMinAmountToSell(
        address _token,
        uint256 _minAmountToSell
    ) internal virtual {
        minAmountToSell[_token] = _minAmountToSell;
    }
}
