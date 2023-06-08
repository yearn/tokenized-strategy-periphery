// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Setup} from "./utils/Setup.sol";

import {CommonReportTrigger} from "../ReportTrigger/CommonReportTrigger.sol";

contract CommonTriggerTest is Setup {
    CommonReportTrigger public commonTrigger;

    function setUp() public override {
        super.setUp();

        commonTrigger = new CommonReportTrigger(management);
    }

    function test_setup() public {
        assertEq(commonTrigger.owner(), address(management));
        assertEq(commonTrigger.baseFeeProvider(), address(0));
        assertEq(commonTrigger.acceptableBaseFee(), 0);
        assertEq(
            commonTrigger.customStrategyTrigger(address(mockStrategy)),
            address(0)
        );
        assertEq(
            commonTrigger.customVaultTrigger(
                address(vault),
                address(mockStrategy)
            ),
            address(0)
        );
    }
}
