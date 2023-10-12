// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {BaseStrategy, ERC20} from "@tokenized-strategy/BaseStrategy.sol";

contract MockStrategy is BaseStrategy {
    bool public tendStatus;

    constructor(address _asset) BaseStrategy(_asset, "Mock Basic Strategy") {}

    function _deployFunds(uint256) internal override {}

    function _freeFunds(uint256) internal override {}

    function _harvestAndReport()
        internal
        override
        returns (uint256 _totalAssets)
    {
        _totalAssets = asset.balanceOf(address(this));
    }

    function _tendTrigger() internal view override returns (bool) {
        return tendStatus;
    }

    function setTendStatus(bool _status) external {
        tendStatus = _status;
    }
}
