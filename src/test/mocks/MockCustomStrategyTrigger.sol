// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {CustomStrategyTriggerBase} from "../../ReportTrigger/CustomStrategyTriggerBase.sol";

contract MockCustomStrategyTrigger is CustomStrategyTriggerBase {
    bool public triggerStatus;

    function reportTrigger(
        address /*_strategy*/
    ) external view override returns (bool, bytes memory) {
        return (triggerStatus, bytes("Test trigger status"));
    }

    function setTriggerStatus(bool _status) external {
        triggerStatus = _status;
    }
}
