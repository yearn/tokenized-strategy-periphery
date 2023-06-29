// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Setup, IStrategy, console} from "./utils/Setup.sol";

import {CommonReportTrigger, IBaseFee} from "../ReportTrigger/CommonReportTrigger.sol";
import {MockCustomStrategyTrigger} from "./mocks/MockCustomStrategyTrigger.sol";
import {MockCustomVaultTrigger} from "./mocks/MockCustomVaultTrigger.sol";

interface IStrategys {
    function report() external returns (uint256, uint256);
}

contract CommonTriggerTest is Setup {
    CommonReportTrigger public commonTrigger;
    MockCustomStrategyTrigger public customStrategyTrigger;
    MockCustomVaultTrigger public customVaultTrigger;

    address public baseFeeProvider = 0xe0514dD71cfdC30147e76f65C30bdF60bfD437C3;

    function setUp() public override {
        super.setUp();

        commonTrigger = new CommonReportTrigger(daddy);
        customStrategyTrigger = new MockCustomStrategyTrigger();
        customVaultTrigger = new MockCustomVaultTrigger();
    }

    function test_setup() public {
        assertEq(commonTrigger.governance(), address(daddy));
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

    function test_addBaseFeeProvider(address _address) public {
        vm.assume(_address != daddy);

        assertEq(commonTrigger.baseFeeProvider(), address(0));

        vm.expectRevert("!governance");
        vm.prank(_address);
        commonTrigger.setBaseFeeProvider(baseFeeProvider);

        assertEq(commonTrigger.baseFeeProvider(), address(0));

        vm.prank(daddy);
        commonTrigger.setBaseFeeProvider(baseFeeProvider);

        assertEq(commonTrigger.baseFeeProvider(), baseFeeProvider);
    }

    function test_addAcceptableBaseFee(
        address _address,
        uint256 _amount
    ) public {
        vm.assume(_address != daddy);
        vm.assume(_amount != 0);

        assertEq(commonTrigger.acceptableBaseFee(), 0);

        vm.expectRevert("!governance");
        vm.prank(_address);
        commonTrigger.setAcceptableBaseFee(_amount);

        assertEq(commonTrigger.acceptableBaseFee(), 0);

        vm.prank(daddy);
        commonTrigger.setAcceptableBaseFee(_amount);

        assertEq(commonTrigger.acceptableBaseFee(), _amount);
    }

    function test_transferGovernance(
        address _caller,
        address _newOwner
    ) public {
        vm.assume(_caller != daddy);
        vm.assume(_newOwner != daddy && _newOwner != address(0));

        assertEq(commonTrigger.governance(), daddy);

        vm.expectRevert("!governance");
        vm.prank(_caller);
        commonTrigger.transferGovernance(_newOwner);

        assertEq(commonTrigger.governance(), daddy);

        vm.expectRevert("ZERO ADDRESS");
        vm.prank(daddy);
        commonTrigger.transferGovernance(address(0));

        assertEq(commonTrigger.governance(), daddy);

        vm.prank(daddy);
        commonTrigger.transferGovernance(_newOwner);

        assertEq(commonTrigger.governance(), _newOwner);
    }

    function test_setCustomStrategyTrigger(address _address) public {
        vm.assume(_address != management);

        assertEq(
            commonTrigger.customStrategyTrigger(address(mockStrategy)),
            address(0)
        );

        vm.expectRevert("!authorized");
        vm.prank(_address);
        commonTrigger.setCustomStrategyTrigger(
            address(mockStrategy),
            address(customStrategyTrigger)
        );

        assertEq(
            commonTrigger.customStrategyTrigger(address(mockStrategy)),
            address(0)
        );

        vm.prank(management);
        commonTrigger.setCustomStrategyTrigger(
            address(mockStrategy),
            address(customStrategyTrigger)
        );

        assertEq(
            commonTrigger.customStrategyTrigger(address(mockStrategy)),
            address(customStrategyTrigger)
        );
    }

    function test_setCustomVaultTrigger(address _address) public {
        vm.assume(_address != vaultManagement);

        assertEq(
            commonTrigger.customVaultTrigger(
                address(vault),
                address(mockStrategy)
            ),
            address(0)
        );

        vm.expectRevert("!authorized");
        vm.prank(_address);
        commonTrigger.setCustomVaultTrigger(
            address(vault),
            address(mockStrategy),
            address(customVaultTrigger)
        );

        assertEq(
            commonTrigger.customVaultTrigger(
                address(vault),
                address(mockStrategy)
            ),
            address(0)
        );

        vm.prank(vaultManagement);
        commonTrigger.setCustomVaultTrigger(
            address(vault),
            address(mockStrategy),
            address(customVaultTrigger)
        );

        assertEq(
            commonTrigger.customVaultTrigger(
                address(vault),
                address(mockStrategy)
            ),
            address(customVaultTrigger)
        );
    }

    function test_setCustomStrategyBaseFee(
        address _address,
        uint256 _baseFee
    ) public {
        vm.assume(_address != management);
        vm.assume(_baseFee != 0);

        assertEq(commonTrigger.customStrategyBaseFee(address(mockStrategy)), 0);

        vm.expectRevert("!authorized");
        vm.prank(_address);
        commonTrigger.setCustomStrategyBaseFee(address(mockStrategy), _baseFee);

        assertEq(commonTrigger.customStrategyBaseFee(address(mockStrategy)), 0);

        vm.prank(management);
        commonTrigger.setCustomStrategyBaseFee(address(mockStrategy), _baseFee);

        assertEq(
            commonTrigger.customStrategyBaseFee(address(mockStrategy)),
            _baseFee
        );
    }

    function test_setCustomVaultBaseFee(
        address _address,
        uint256 _baseFee
    ) public {
        vm.assume(_address != management);
        vm.assume(_baseFee != 0);

        assertEq(
            commonTrigger.customVaultBaseFee(
                address(vault),
                address(mockStrategy)
            ),
            0
        );

        vm.expectRevert("!authorized");
        vm.prank(_address);
        commonTrigger.setCustomVaultBaseFee(
            address(vault),
            address(mockStrategy),
            _baseFee
        );

        assertEq(
            commonTrigger.customVaultBaseFee(
                address(vault),
                address(mockStrategy)
            ),
            0
        );

        vm.prank(vaultManagement);
        commonTrigger.setCustomVaultBaseFee(
            address(vault),
            address(mockStrategy),
            _baseFee
        );

        assertEq(
            commonTrigger.customVaultBaseFee(
                address(vault),
                address(mockStrategy)
            ),
            _baseFee
        );
    }

    function test_defualtStrategyTrigger(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        bytes memory _calldata = abi.encodeWithSelector(
            mockStrategy.report.selector
        );

        // Set up base fee provider.
        vm.prank(daddy);
        commonTrigger.setBaseFeeProvider(baseFeeProvider);
        assertEq(commonTrigger.baseFeeProvider(), baseFeeProvider);

        // Set base fee.
        uint256 currentBase = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        commonTrigger.setAcceptableBaseFee(currentBase * 2);

        // Test when nothing has happened. Should be false.
        bool response;
        bytes memory data;
        (response, data) = commonTrigger.strategyReportTrigger(
            address(mockStrategy)
        );
        assertEq(response, false);
        assertEq(data, bytes("Zero Assets"));

        // Deposit into the strategy.
        mintAndDepositIntoStrategy(
            IStrategy(address(mockStrategy)),
            user,
            _amount
        );

        // Skip time for report
        skip(mockStrategy.profitMaxUnlockTime() + 1);

        (response, data) = commonTrigger.strategyReportTrigger(
            address(mockStrategy)
        );
        assertEq(response, true);
        assertEq(data, _calldata);

        // base fee not acceptable
        // lower acceptable base fee.
        currentBase = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        commonTrigger.setAcceptableBaseFee(currentBase / 2);

        (response, data) = commonTrigger.strategyReportTrigger(
            address(mockStrategy)
        );
        assertEq(response, false);
        assertEq(data, bytes("Base Fee"));

        currentBase = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        commonTrigger.setAcceptableBaseFee(currentBase * 2);

        (response, data) = commonTrigger.strategyReportTrigger(
            address(mockStrategy)
        );
        assertEq(response, true);
        assertEq(data, _calldata);

        // Withdraw funds
        vm.prank(user);
        mockStrategy.redeem(_amount, user, user);
        //Should be false with total Assets = 0.
        (response, data) = commonTrigger.strategyReportTrigger(
            address(mockStrategy)
        );
        assertEq(response, false);
        assertEq(data, bytes("Zero Assets"));

        // Deposit back in.
        depositIntoStrategy(IStrategy(address(mockStrategy)), user, _amount);

        (response, data) = commonTrigger.strategyReportTrigger(
            address(mockStrategy)
        );
        assertEq(response, true);
        assertEq(data, _calldata);

        // Shutdown
        vm.prank(management);
        mockStrategy.shutdownStrategy();

        (response, data) = commonTrigger.strategyReportTrigger(
            address(mockStrategy)
        );
        assertEq(response, false);
        assertEq(data, bytes("Shutdown"));
    }

    function test_defualtVaultTrigger(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        bytes memory _calldata = abi.encodeWithSelector(
            vault.process_report.selector,
            address(mockStrategy)
        );
        bool response;
        bytes memory data;

        // Set up base fee provider.
        vm.prank(daddy);
        commonTrigger.setBaseFeeProvider(baseFeeProvider);
        assertEq(commonTrigger.baseFeeProvider(), baseFeeProvider);

        // Set base fee.
        uint256 currentBase = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        commonTrigger.setAcceptableBaseFee(currentBase * 2);

        // Test when nothing has happened. Should be false.
        (response, data) = commonTrigger.vaultReportTrigger(
            address(vault),
            address(mockStrategy)
        );
        assertEq(response, false);
        assertEq(data, bytes("Not Active"));

        // Setup strategy and give it debt through the vault.
        addStrategyAndDebt(
            vault,
            IStrategy(address(mockStrategy)),
            user,
            _amount
        );

        // Skip time for report trigger
        skip(vault.profitMaxUnlockTime() + 1);

        (response, data) = commonTrigger.vaultReportTrigger(
            address(vault),
            address(mockStrategy)
        );
        assertEq(response, true);
        assertEq(data, _calldata);

        // lower acceptable base fee.
        currentBase = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        commonTrigger.setAcceptableBaseFee(currentBase / 2);

        (response, data) = commonTrigger.vaultReportTrigger(
            address(vault),
            address(mockStrategy)
        );
        assertEq(response, false);
        assertEq(data, bytes("Base Fee"));

        // Reset it
        currentBase = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        commonTrigger.setAcceptableBaseFee(currentBase * 2);

        (response, data) = commonTrigger.vaultReportTrigger(
            address(vault),
            address(mockStrategy)
        );
        assertEq(response, true);
        assertEq(data, _calldata);

        // Withdraw funds
        addDebtToStrategy(vault, IStrategy(address(mockStrategy)), 0);
        //Should be false with currentDebt = 0.
        (response, data) = commonTrigger.vaultReportTrigger(
            address(vault),
            address(mockStrategy)
        );
        assertEq(response, false);
        assertEq(data, bytes("Not Active"));

        // Deposit back in.
        addDebtToStrategy(vault, IStrategy(address(mockStrategy)), _amount);
        (response, data) = commonTrigger.vaultReportTrigger(
            address(vault),
            address(mockStrategy)
        );
        assertEq(response, true);
        assertEq(data, _calldata);

        // Shutdown
        vm.prank(vaultManagement);
        vault.shutdown_vault();
        (response, data) = commonTrigger.vaultReportTrigger(
            address(vault),
            address(mockStrategy)
        );
        assertEq(response, false);
        assertEq(data, bytes("Shutdown"));
    }

    function test_tendTrigger(bool _status) public {
        bytes memory _calldata = abi.encodeWithSelector(
            mockStrategy.tend.selector
        );

        bool response;
        bytes memory data;

        (response, data) = commonTrigger.strategyTendTrigger(
            address(mockStrategy)
        );

        assertEq(response, false);
        assertEq(data, _calldata);

        address(mockStrategy).call(
            abi.encodeWithSignature("setTendStatus(bool)", _status)
        );

        (response, data) = commonTrigger.strategyTendTrigger(
            address(mockStrategy)
        );

        assertEq(response, _status);
        assertEq(data, _calldata);
    }
}
