// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {AuctionSwapper, Auction, SafeERC20} from "../../swappers/AuctionSwapper.sol";
import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";

contract MockAuctionSwapper is BaseStrategy, AuctionSwapper {
    using SafeERC20 for ERC20;

    bool public useDefault = true;

    uint256 public letKick;

    address[] internal _protectedTokens;

    constructor(address _asset) BaseStrategy(_asset, "Mock Uni V3") {}

    function _deployFunds(uint256) internal override {}

    function _freeFunds(uint256) internal override {}

    function _harvestAndReport() internal override returns (uint256 _reportedAssets) {
        _reportedAssets = asset.balanceOf(address(this));
    }

    function _strategyTotalAssets() internal view override returns (uint256) {
        return asset.balanceOf(address(this));
    }

    function setAuction(address _auction) external onlyManagement {
        _setAuction(_auction);
    }

    function setUseAuction(bool _useAuction) external onlyManagement {
        _setUseAuction(_useAuction);
    }

    function setMinAmountToSell(address _token, uint256 _minAmountToSell) external {
        _setMinAmountToSell(_token, _minAmountToSell);
    }

    function protectedTokens() public view override returns (address[] memory) {
        return _protectedTokens;
    }

    function setProtectedTokens(address[] calldata _tokens) external {
        delete _protectedTokens;

        uint256 length = _tokens.length;
        for (uint256 i; i < length; ++i) {
            _protectedTokens.push(_tokens[i]);
        }
    }

    function kickable(address _token) public view override returns (uint256) {
        if (_isProtectedToken(_token)) return 0;
        if (useDefault) return super.kickable(_token);
        return letKick;
    }

    function kickAuction(address _token) external override returns (uint256) {
        require(!_isProtectedToken(_token), "protected token");
        if (useDefault) return _kickAuction(_token);

        ERC20(_token).safeTransfer(auction, letKick);
        return Auction(auction).kick(_token);
    }

    function setUseDefault(bool _useDefault) external {
        useDefault = _useDefault;
    }

    function setLetKick(uint256 _letKick) external {
        letKick = _letKick;
    }
}

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IAuctionSwapper} from "../../swappers/interfaces/IAuctionSwapper.sol";

interface IMockAuctionSwapper is IStrategy, IAuctionSwapper {
    function setAuction(address _auction) external;

    function setUseAuction(bool _useAuction) external;

    function setMinAmountToSell(address _token, uint256 _minAmountToSell) external;

    function setProtectedTokens(address[] calldata _tokens) external;

    function useDefault() external view returns (bool);

    function setUseDefault(bool _useDefault) external;

    function letKick() external view returns (uint256);

    function setLetKick(uint256 _letKick) external;

    function kickAuction(address _token) external returns (uint256);

    function kickable(address _token) external view returns (uint256);
}
