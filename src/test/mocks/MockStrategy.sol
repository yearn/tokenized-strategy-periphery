// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BaseTokenizedStrategy} from "@tokenized-strategy/BaseTokenizedStrategy.sol";

contract MockStrategy is BaseTokenizedStrategy {
    constructor(
        address _asset
    ) BaseTokenizedStrategy(_asset, "Mock Basic Strategy") {}

    function _deployFunds(uint256) internal override {}

    function _freeFunds(uint256) internal override {}

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = ERC20(asset).balanceOf(address(this));
    }
}
