// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {ITradeFactory} from "../interfaces/TradeFactory/ITradeFactory.sol";

abstract contract TradeFactorySwapper {
    using SafeERC20 for ERC20;

    address private _tradeFactory;

    address[] private _rewardTokens;

    // We use a getter so trade factory can only be set through the
    // proper functions to avoid issues.
    function tradeFactory() public view returns (address) {
        return _tradeFactory;
    }

    function rewardTokens() public view returns (address[] memory) {
        return _rewardTokens;
    }

    function _addTokens(address[] memory _from, address[] memory _to) internal {
        for (uint256 i; i < _from.length; ++i) {
            _addToken(_from[i], _to[i]);
        }
    }

    function _addToken(address _tokenFrom, address _tokenTo) internal {
        address tradeFactory_ = _tradeFactory;
        if (tradeFactory_ != address(0)) {
            ERC20(_tokenFrom).safeApprove(tradeFactory_, type(uint256).max);

            ITradeFactory(tradeFactory_).enable(_tokenFrom, _tokenTo);
        }

        _rewardTokens.push(_tokenFrom);
    }

    function _removeToken(address _tokenFrom, address _tokenTo) internal {
        address[] memory rewardTokens_ = _rewardTokens;
        for (uint256 i; i < rewardTokens_.length; ++i) {
            if (rewardTokens_[i] == _tokenFrom) {
                if (i != rewardTokens_.length - 1) {
                    // if it isn't the last token, swap with the last one/
                    rewardTokens_[i] = rewardTokens_[rewardTokens_.length - 1];
                }
                ERC20(_tokenFrom).safeApprove(_tradeFactory, 0);
                ITradeFactory(_tradeFactory).disable(_tokenFrom, _tokenTo);

                _rewardTokens = _rewardTokens;
                _rewardTokens.pop();
            }
        }
    }

    function _deleteRewardTokens() internal {
        _removeTradeFactoryPermissions();
        delete _rewardTokens;
    }

    function _setTradeFactory(
        address tradeFactory_,
        address _tokenTo
    ) internal {
        if (_tradeFactory != address(0)) {
            _removeTradeFactoryPermissions();
        }

        address[] memory rewardTokens_ = _rewardTokens;
        ITradeFactory tf = ITradeFactory(tradeFactory_);

        // TODO: Dont iterate over the array twice
        for (uint256 i; i < rewardTokens_.length; ++i) {
            address token = rewardTokens_[i];

            ERC20(token).safeApprove(tradeFactory_, type(uint256).max);

            tf.enable(token, _tokenTo);
        }

        _tradeFactory = tradeFactory_;
    }

    function _removeTradeFactoryPermissions() internal {
        address[] memory rewardTokens_ = _rewardTokens;
        for (uint256 i; i < rewardTokens_.length; ++i) {
            ERC20(rewardTokens_[i]).safeApprove(_tradeFactory, 0);
            // TODO: Add a disable
        }

        _tradeFactory = address(0);
    }

    // Used for TradeFactory to claim rewards
    function claimRewards() external {
        require(msg.sender == _tradeFactory, "!authorized");
        _claimRewards();
    }

    // Need to be overridden to claim rewards mid report cycles.
    function _claimRewards() internal virtual;
}
