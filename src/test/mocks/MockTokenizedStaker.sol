// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {TokenizedStaker} from "../../Bases/Staker/TokenizedStaker.sol";
import {ITokenizedStaker} from "../../Bases/Staker/ITokenizedStaker.sol";

contract MockTokenizedStaker is TokenizedStaker {
    constructor(
        address _asset,
        string memory _name
    ) TokenizedStaker(_asset, _name) {}

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

interface IMockTokenizedStaker is ITokenizedStaker {}
