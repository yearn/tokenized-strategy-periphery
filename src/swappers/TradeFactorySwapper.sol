// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITradeFactory} from "../interfaces/TradeFactory/ITradeFactory.sol";

/**
 * @title Trade Factory Swapper
 * @dev Inherit to use a Trade Factory for token swapping.
 *   External functions with the proper modifiers should be
 *   declared in the strategy that inherits this to add a
 *   Trade Factory and the tokens to sell.
 */
abstract contract TradeFactorySwapper {
    using SafeERC20 for ERC20;

    // Address of the trade factory in use if any.
    address private _tradeFactory;

    // Array of any tokens added to be sold.
    address[] private _rewardTokens;

    /**
     * @notice Get the current Trade Factory.
     * @dev We use a getter so trade factory can only be set through the
     *   proper functions to avoid issues.
     * @return The current trade factory in use if any.
     */
    function tradeFactory() public view virtual returns (address) {
        return _tradeFactory;
    }

    /**
     * @notice Get the current tokens being sold through the Trade Factory.
     * @dev We use a getter so the array can only be set through the
     *   proper functions to avoid issues.
     * @return The current array of tokens being sold if any.
     */
    function rewardTokens() public view virtual returns (address[] memory) {
        return _rewardTokens;
    }

    /**
     * @dev Add an array of tokens to sell to its corresponding `_to_.
     */
    function _addTokens(
        address[] memory _from,
        address[] memory _to
    ) internal virtual {
        for (uint256 i; i < _from.length; ++i) {
            _addToken(_from[i], _to[i]);
        }
    }

    /**
     * @dev Add the `_tokenFrom` to be sold to `_tokenTo` through the Trade Factory
     */
    function _addToken(address _tokenFrom, address _tokenTo) internal virtual {
        address _tf = tradeFactory();
        if (_tf != address(0)) {
            ERC20(_tokenFrom).forceApprove(_tf, type(uint256).max);
            ITradeFactory(_tf).enable(_tokenFrom, _tokenTo);
        }

        _rewardTokens.push(_tokenFrom);
    }

    /**
     * @dev Remove a specific `_tokenFrom` that was previously added to not be
     * sold through the Trade Factory any more.
     */
    function _removeToken(
        address _tokenFrom,
        address _tokenTo
    ) internal virtual {
        address _tf = tradeFactory();
        address[] memory _rewardTokensLocal = rewardTokens();
        for (uint256 i; i < _rewardTokensLocal.length; ++i) {
            if (_rewardTokensLocal[i] == _tokenFrom) {
                if (i != _rewardTokensLocal.length - 1) {
                    // if it isn't the last token, swap with the last one/
                    _rewardTokensLocal[i] = _rewardTokensLocal[
                        _rewardTokensLocal.length - 1
                    ];
                }

                if (_tf != address(0)) {
                    ERC20(_tokenFrom).forceApprove(_tf, 0);
                    ITradeFactory(_tf).disable(_tokenFrom, _tokenTo);
                }

                // Set to storage
                _rewardTokens = _rewardTokensLocal;
                _rewardTokens.pop();
            }
        }
    }

    /**
     * @dev Removes all reward tokens and delete the Trade Factory.
     */
    function _deleteRewardTokens() internal virtual {
        _removeTradeFactoryPermissions();
        delete _rewardTokens;
    }

    /**
     * @dev Set a new instance of the Trade Factory.
     *   This will remove any old approvals for current factory if any.
     *   Then will add the new approvals for the new Trade Factory.
     *   Can pass in address(0) for `tradeFactory_` to remove all permissions.
     */
    function _setTradeFactory(
        address tradeFactory_,
        address _tokenTo
    ) internal virtual {
        address _tf = tradeFactory();

        // Remove any old Trade Factory
        if (_tf != address(0)) {
            _removeTradeFactoryPermissions();
        }

        // If setting to address(0) we are done.
        if (tradeFactory_ == address(0)) return;

        address[] memory _rewardTokensLocal = _rewardTokens;

        for (uint256 i; i < _rewardTokensLocal.length; ++i) {
            address token = _rewardTokensLocal[i];

            ERC20(token).forceApprove(tradeFactory_, type(uint256).max);
            ITradeFactory(tradeFactory_).enable(token, _tokenTo);
        }

        // Set to storage
        _tradeFactory = tradeFactory_;
    }

    /**
     * @dev Remove any active approvals and set the trade factory to address(0).
     */
    function _removeTradeFactoryPermissions() internal virtual {
        address _tf = tradeFactory();
        address[] memory rewardTokensLocal = rewardTokens();
        for (uint256 i; i < rewardTokensLocal.length; ++i) {
            ERC20(rewardTokensLocal[i]).forceApprove(_tf, 0);
        }

        _tradeFactory = address(0);
    }

    /**
     * @notice Used for TradeFactory to claim rewards.
     */
    function claimRewards() external virtual {
        require(msg.sender == _tradeFactory, "!authorized");
        _claimRewards();
    }

    /**
     * @dev Need to be overridden to claim rewards mid report cycles.
     */
    function _claimRewards() internal virtual;
}
