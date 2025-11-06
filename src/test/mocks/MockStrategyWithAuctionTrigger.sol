// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {IAuctionSwapper} from "../../swappers/interfaces/IAuctionSwapper.sol";
import {MockStrategy} from "./MockStrategy.sol";

contract MockStrategyWithAuctionTrigger is MockStrategy {
    bool public auctionReady;
    bool public returnCalldata;
    bool public shouldRevertOnAuctionTrigger;

    constructor(address _asset) MockStrategy(_asset) {}

    function auctionTrigger(
        address _from
    ) external view returns (bool, bytes memory) {
        if (shouldRevertOnAuctionTrigger) {
            revert("Strategy auction trigger reverted");
        }

        if (!auctionReady) {
            return (false, bytes("Not Ready"));
        }

        if (returnCalldata) {
            return (
                true,
                abi.encodeWithSignature("kickAuction(address)", _from)
            );
        }

        return (true, bytes("Ready"));
    }

    function setAuctionReady(bool _ready) external {
        auctionReady = _ready;
    }

    function setReturnCalldata(bool _return) external {
        returnCalldata = _return;
    }

    function setShouldRevertOnAuctionTrigger(bool _shouldRevert) external {
        shouldRevertOnAuctionTrigger = _shouldRevert;
    }
}
