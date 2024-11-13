// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {AuctionSwapper, Auction, SafeERC20} from "../../swappers/AuctionSwapper.sol";
import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";

contract MockAuctionSwapper is BaseStrategy, AuctionSwapper {
    using SafeERC20 for ERC20;

    event PreTake(address token, uint256 amountToTake, uint256 amountToPay);
    event PostTake(address token, uint256 amountTaken, uint256 amountPayed);

    bool public useDefault = true;

    uint256 public letKick;

    constructor(address _asset) BaseStrategy(_asset, "Mock Uni V3") {}

    function _deployFunds(uint256) internal override {}

    function _freeFunds(uint256) internal override {}

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = asset.balanceOf(address(this));
    }

    function enableAuction(address _from, address _to) external {
        _enableAuction(_from, _to);
    }

    function disableAuction(address _from) external {
        _disableAuction(_from);
    }

    function kickable(address _token) public view override returns (uint256) {
        if (useDefault) return super.kickable(_token);
        return letKick;
    }

    function kickAuction(address _token) external returns (uint256) {
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
    function enableAuction(address _from, address _to) external;

    function disableAuction(address _from) external;

    function useDefault() external view returns (bool);

    function setUseDefault(bool _useDefault) external;

    function letKick() external view returns (uint256);

    function setLetKick(uint256 _letKick) external;

    function kickAuction(address _token) external returns (uint256);

    function kickable(address _token) external view returns (uint256);
}
