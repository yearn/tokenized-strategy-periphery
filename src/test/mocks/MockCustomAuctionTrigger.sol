// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.18;

import {ICustomAuctionTrigger} from "../../ReportTrigger/CommonTrigger.sol";

contract MockCustomAuctionTrigger is ICustomAuctionTrigger {
    bool public shouldKick;
    bool public shouldRevert;

    function auctionTrigger(
        address /* _strategy */,
        address /* _from */
    ) external view override returns (bool, bytes memory) {
        if (shouldRevert) {
            revert("Custom trigger reverted");
        }

        if (!shouldKick) {
            return (false, bytes("Custom Not Ready"));
        }

        return (true, bytes("Custom Kick"));
    }

    function setShouldKick(bool _kick) external {
        shouldKick = _kick;
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
