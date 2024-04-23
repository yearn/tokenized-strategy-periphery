// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {BaseAuctioneer, SafeERC20} from "../../Bases/Auctioneer/BaseAuctioneer.sol";
import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";

contract MockAuctioneer is BaseAuctioneer {
    using SafeERC20 for ERC20;

    event PreTake(address token, uint256 amountToTake, uint256 amountToPay);
    event PostTake(address token, uint256 amountTaken, uint256 amountPayed);

    bool public useDefault = true;

    bool public shouldRevert;

    uint256 public letKick;

    constructor(
        address _asset
    ) BaseAuctioneer(_asset, "Mock Auctioneer", _asset, 1 days, 5 days, 1e7) {}

    function _deployFunds(uint256) internal override {}

    function _freeFunds(uint256) internal override {}

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = asset.balanceOf(address(this));
    }

    function _kickable(
        address _token
    ) internal view override returns (uint256) {
        if (useDefault) return super._kickable(_token);
        return letKick;
    }

    function _auctionKicked(
        address _token
    ) internal override returns (uint256) {
        if (useDefault) return super._auctionKicked(_token);
        return letKick;
    }

    function _preTake(
        address _token,
        uint256 _amountToTake,
        uint256 _amountToPay
    ) internal override {
        require(!shouldRevert, "pre take revert");
        if (useDefault) return;
        emit PreTake(_token, _amountToTake, _amountToPay);
    }

    function _postTake(
        address _token,
        uint256 _amountTaken,
        uint256 _amountPayed
    ) internal override {
        require(!shouldRevert, "post take revert");
        if (useDefault) return;
        emit PostTake(_token, _amountTaken, _amountPayed);
    }

    function setUseDefault(bool _useDefault) external {
        useDefault = _useDefault;
    }

    function setLetKick(uint256 _letKick) external {
        letKick = _letKick;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
}

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IBaseAuctioneer} from "../../Bases/Auctioneer/IBaseAuctioneer.sol";

interface IMockAuctioneer is IStrategy, IBaseAuctioneer {
    function useDefault() external view returns (bool);

    function setUseDefault(bool _useDefault) external;

    function letKick() external view returns (uint256);

    function setLetKick(uint256 _letKick) external;

    function setShouldRevert(bool _shouldRevert) external;
}
