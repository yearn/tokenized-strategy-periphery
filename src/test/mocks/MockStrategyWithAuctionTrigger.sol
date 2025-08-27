// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {IStrategyAuctionTrigger} from "../../AuctionTrigger/CommonAuctionTrigger.sol";
import {MockStrategy} from "./MockStrategy.sol";

contract MockStrategyWithAuctionTrigger is
    MockStrategy,
    IStrategyAuctionTrigger
{
    bool public auctionTriggerStatus;
    bytes public auctionTriggerData;
    bool public shouldRevertOnAuctionTrigger;

    constructor(address _asset) MockStrategy(_asset) {}

    function auctionTrigger(
        address /* _from */
    ) external view override returns (bool, bytes memory) {
        if (shouldRevertOnAuctionTrigger) {
            revert("Strategy auction trigger reverted");
        }

        return (auctionTriggerStatus, auctionTriggerData);
    }

    function setAuctionTriggerStatus(bool _status) external {
        auctionTriggerStatus = _status;
    }

    function setAuctionTriggerData(bytes calldata _data) external {
        auctionTriggerData = _data;
    }

    function setShouldRevertOnAuctionTrigger(bool _shouldRevert) external {
        shouldRevertOnAuctionTrigger = _shouldRevert;
    }
}
