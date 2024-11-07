// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {BaseAuctioneer} from "../../Bases/Auctioneer/BaseAuctioneer.sol";
import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";

contract MockAuctioneer is BaseAuctioneer {
    using SafeERC20 for ERC20;

    constructor(
        address _asset
    ) BaseAuctioneer(_asset, "Mock Auctioneer", msg.sender, 1 days, 1e7) {}

    function _deployFunds(uint256) internal override {}

    function _freeFunds(uint256) internal override {}

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = asset.balanceOf(address(this));
    }
}

import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {IBaseAuctioneer} from "../../Bases/Auctioneer/IBaseAuctioneer.sol";

interface IMockAuctioneer is IStrategy, IBaseAuctioneer {}
