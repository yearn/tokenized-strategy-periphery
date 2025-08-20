// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {ICustomAuctionTrigger} from "../../AuctionTrigger/CommonAuctionTrigger.sol";

contract MockCustomAuctionTrigger is ICustomAuctionTrigger {
    bool public triggerStatus;
    bytes public triggerData;
    bool public shouldRevert;

    function auctionTrigger(
        address /* _strategy */,
        address /* _from */
    ) external view override returns (bool, bytes memory) {
        if (shouldRevert) {
            revert("Custom trigger reverted");
        }

        return (triggerStatus, triggerData);
    }

    function setTriggerStatus(bool _status) external {
        triggerStatus = _status;
    }

    function setTriggerData(bytes calldata _data) external {
        triggerData = _data;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
}

// Contract to test reverts in custom triggers
contract RevertingCustomTrigger is ICustomAuctionTrigger {
    function auctionTrigger(
        address /* _strategy */,
        address /* _from */
    ) external pure override returns (bool, bytes memory) {
        revert("Always reverts");
    }
}
