// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, IStrategy, console, Roles} from "./utils/Setup.sol";

import {CommonTrigger, IBaseFee, ICustomAuctionTrigger, IAuctionSwapper} from "../ReportTrigger/CommonTrigger.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {MockCustomStrategyTrigger} from "./mocks/MockCustomStrategyTrigger.sol";
import {MockCustomVaultTrigger} from "./mocks/MockCustomVaultTrigger.sol";
import {MockCustomAuctionTrigger} from "./mocks/MockCustomAuctionTrigger.sol";
import {MockStrategyWithAuctionTrigger} from "./mocks/MockStrategyWithAuctionTrigger.sol";

contract CommonTriggerTest is Setup {
    CommonTrigger public commonTrigger;
    MockCustomStrategyTrigger public customStrategyTrigger;
    MockCustomVaultTrigger public customVaultTrigger;
    MockCustomAuctionTrigger public customAuctionTrigger;
    MockStrategyWithAuctionTrigger public strategyWithAuctionTrigger;

    address public baseFeeProvider = 0xe0514dD71cfdC30147e76f65C30bdF60bfD437C3;
    address public fromToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

    function setUp() public override {
        super.setUp();

        commonTrigger = new CommonTrigger(daddy);
        customStrategyTrigger = new MockCustomStrategyTrigger();
        customVaultTrigger = new MockCustomVaultTrigger();
        customAuctionTrigger = new MockCustomAuctionTrigger();

        strategyWithAuctionTrigger = new MockStrategyWithAuctionTrigger(
            address(asset)
        );
        _setupStrategy(strategyWithAuctionTrigger);
    }

    function _setupStrategy(MockStrategyWithAuctionTrigger strategy) internal {
        IStrategy(address(strategy)).setKeeper(keeper);
        IStrategy(address(strategy)).setPerformanceFeeRecipient(
            performanceFeeRecipient
        );
        IStrategy(address(strategy)).setPendingManagement(management);
        vm.prank(management);
        IStrategy(address(strategy)).acceptManagement();
    }

    function test_setup() public {
        // Deploy a vault.
        vault = setUpVault();

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

    function test_setCustomVaultTrigger() public {
        // Deploy a vault.
        vault = setUpVault();

        assertEq(
            commonTrigger.customVaultTrigger(
                address(vault),
                address(mockStrategy)
            ),
            address(0)
        );

        vm.expectRevert("!authorized");
        vm.prank(user);
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

        // Give the user the reporting manager role.
        vm.prank(management);
        vault.set_role(user, Roles.REPORTING_MANAGER);

        vm.prank(user);
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

    function test_setCustomVaultBaseFee() public {
        uint256 _baseFee = 67852;

        // Deploy a vault.
        vault = setUpVault();

        assertEq(
            commonTrigger.customVaultBaseFee(
                address(vault),
                address(mockStrategy)
            ),
            0
        );

        vm.expectRevert("!authorized");
        vm.prank(user);
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

        // Give the user the reporting manager role.
        vm.prank(management);
        vault.set_role(user, Roles.REPORTING_MANAGER);

        vm.prank(user);
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

    function test_defaultStrategyTrigger(uint256 _amount) public {
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

    function test_defaultVaultTrigger() public {
        uint256 _amount = 1e18;

        // Deploy a vault.
        vault = setUpVault();

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

    /*//////////////////////////////////////////////////////////////
                        AUCTION TRIGGER TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setCustomAuctionTrigger() public {
        assertEq(
            commonTrigger.customAuctionTrigger(
                address(strategyWithAuctionTrigger)
            ),
            address(0)
        );

        // Test unauthorized user
        vm.expectRevert("!authorized");
        vm.prank(user);
        commonTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(customAuctionTrigger)
        );

        assertEq(
            commonTrigger.customAuctionTrigger(
                address(strategyWithAuctionTrigger)
            ),
            address(0)
        );

        // Test authorized management
        vm.prank(management);
        commonTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(customAuctionTrigger)
        );

        assertEq(
            commonTrigger.customAuctionTrigger(
                address(strategyWithAuctionTrigger)
            ),
            address(customAuctionTrigger)
        );
    }

    function test_auctionTriggerWithStrategyImplementation() public {
        // Set the auction ready flag in the strategy
        strategyWithAuctionTrigger.setAuctionReady(true);
        strategyWithAuctionTrigger.setReturnCalldata(true);

        // Call auctionTrigger
        (bool shouldKick, bytes memory data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );

        assertTrue(shouldKick);
        assertEq(
            data,
            abi.encodeWithSignature("kickAuction(address)", fromToken)
        );

        // Set auction ready to false
        strategyWithAuctionTrigger.setAuctionReady(false);

        (shouldKick, data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );

        assertFalse(shouldKick);
        assertEq(data, bytes("Not Ready"));
    }

    function test_auctionTriggerWithCustomTrigger() public {
        // Set custom trigger
        vm.prank(management);
        commonTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(customAuctionTrigger)
        );

        // Custom trigger initially returns false
        (bool shouldKick, bytes memory data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );

        assertFalse(shouldKick);
        assertEq(data, bytes("Custom Not Ready"));

        // Enable the custom trigger
        customAuctionTrigger.setShouldKick(true);

        (shouldKick, data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );

        assertTrue(shouldKick);
        assertEq(data, bytes("Custom Kick"));
    }

    function test_auctionTriggerWithBaseFee() public {
        // Set up base fee provider
        vm.prank(daddy);
        commonTrigger.setBaseFeeProvider(baseFeeProvider);

        // Set base fee threshold
        uint256 currentBase = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        commonTrigger.setAcceptableBaseFee(currentBase / 2);

        // Strategy is ready but base fee is too high
        strategyWithAuctionTrigger.setAuctionReady(true);

        (bool shouldKick, bytes memory data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );

        assertFalse(shouldKick);
        assertEq(data, bytes("Base Fee"));

        // Increase acceptable base fee
        vm.prank(daddy);
        commonTrigger.setAcceptableBaseFee(currentBase * 2);

        (shouldKick, data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );

        assertTrue(shouldKick);
    }

    function test_auctionTriggerWithCustomBaseFee() public {
        // Set up base fee provider
        vm.prank(daddy);
        commonTrigger.setBaseFeeProvider(baseFeeProvider);

        uint256 currentBase = IBaseFee(baseFeeProvider).basefee_global();

        // Set global acceptable base fee low
        vm.prank(daddy);
        commonTrigger.setAcceptableBaseFee(currentBase / 2);

        // Strategy is ready but base fee is too high
        strategyWithAuctionTrigger.setAuctionReady(true);

        (bool shouldKick, bytes memory data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );

        assertFalse(shouldKick);
        assertEq(data, bytes("Base Fee"));

        // Set custom base fee for this specific strategy
        vm.prank(management);
        commonTrigger.setCustomStrategyBaseFee(
            address(strategyWithAuctionTrigger),
            currentBase * 2
        );

        // Now it should work with the custom base fee
        (shouldKick, data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );

        assertTrue(shouldKick);
    }

    function test_auctionTriggerNoImplementation() public {
        // Test with a strategy that doesn't implement auctionTrigger
        (bool shouldKick, bytes memory data) = commonTrigger.auctionTrigger(
            address(mockStrategy),
            fromToken
        );

        assertFalse(shouldKick);
        assertEq(data, bytes("Strategy trigger not implemented or reverted"));
    }

    function test_defaultAuctionTrigger() public {
        // Test the default auction trigger logic directly
        strategyWithAuctionTrigger.setAuctionReady(true);
        strategyWithAuctionTrigger.setReturnCalldata(true);

        (bool shouldKick, bytes memory data) = commonTrigger
            .defaultAuctionTrigger(
                address(strategyWithAuctionTrigger),
                fromToken
            );

        assertTrue(shouldKick);
        assertEq(
            data,
            abi.encodeWithSignature("kickAuction(address)", fromToken)
        );
    }

    function test_setMinimumAmountToKick() public {
        // Test unauthorized user cannot set minimum
        vm.expectRevert("!authorized");
        vm.prank(user);
        commonTrigger.setMinimumAmountToKick(
            address(strategyWithAuctionTrigger),
            fromToken,
            1000e6
        );

        // Check minimum is initially 0
        assertEq(
            commonTrigger.minimumAmountToKick(
                address(strategyWithAuctionTrigger),
                fromToken
            ),
            0
        );

        // Test authorized management can set minimum
        vm.prank(management);
        commonTrigger.setMinimumAmountToKick(
            address(strategyWithAuctionTrigger),
            fromToken,
            1000e6
        );

        assertEq(
            commonTrigger.minimumAmountToKick(
                address(strategyWithAuctionTrigger),
                fromToken
            ),
            1000e6
        );

        // Test setting global minimum (address(0))
        vm.prank(management);
        commonTrigger.setMinimumAmountToKick(
            address(strategyWithAuctionTrigger),
            address(0),
            500e6
        );

        assertEq(
            commonTrigger.minimumAmountToKick(
                address(strategyWithAuctionTrigger),
                address(0)
            ),
            500e6
        );
    }

    function test_auctionTriggerWithMinimumAmount() public {
        // Setup: Set minimum amount for the token
        uint256 minimumAmount = 1000e6; // 1000 USDC
        vm.prank(management);
        commonTrigger.setMinimumAmountToKick(
            address(strategyWithAuctionTrigger),
            address(asset), // Using asset as the token
            minimumAmount
        );

        // Strategy is NOT ready, but we have balance > minimum
        // This should still return true because balance check overrides
        strategyWithAuctionTrigger.setAuctionReady(false);
        strategyWithAuctionTrigger.setReturnCalldata(false);

        // Give the strategy balance > minimum amount
        deal(
            address(asset),
            address(strategyWithAuctionTrigger),
            minimumAmount + 1
        );

        (bool shouldKick, bytes memory data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            address(asset)
        );

        // Should return true with kickAuction calldata since balance > minimum
        assertTrue(shouldKick);
        assertEq(
            data,
            abi.encodeCall(
                IAuctionSwapper(address(strategyWithAuctionTrigger))
                    .kickAuction,
                (address(asset))
            )
        );

        // Now test with balance exactly equal to minimum (should not trigger)
        deal(
            address(asset),
            address(strategyWithAuctionTrigger),
            minimumAmount
        );

        (shouldKick, data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            address(asset)
        );

        // Should return false since balance is not > minimum
        assertFalse(shouldKick);
        assertEq(data, bytes("Not Ready"));

        // Test with balance less than minimum
        deal(
            address(asset),
            address(strategyWithAuctionTrigger),
            minimumAmount - 1
        );

        (shouldKick, data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            address(asset)
        );

        // Should return false
        assertFalse(shouldKick);
        assertEq(data, bytes("Not Ready"));

        // Now set strategy ready and test normal flow
        strategyWithAuctionTrigger.setAuctionReady(true);
        strategyWithAuctionTrigger.setReturnCalldata(true);

        (shouldKick, data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            address(asset)
        );

        // Should follow normal strategy trigger since balance <= minimum
        assertTrue(shouldKick);
        assertEq(
            data,
            abi.encodeWithSignature("kickAuction(address)", address(asset))
        );
    }

    function test_globalMinimumFallback() public {
        // Set a global minimum (address(0))
        uint256 globalMinimum = 100e6;
        vm.prank(management);
        commonTrigger.setMinimumAmountToKick(
            address(strategyWithAuctionTrigger),
            address(0),
            globalMinimum
        );

        // Strategy is ready (but this will be overridden if balance > minimum)
        strategyWithAuctionTrigger.setAuctionReady(true);
        strategyWithAuctionTrigger.setReturnCalldata(true);

        // Test with a token that doesn't have a specific minimum
        address otherToken = address(0x123);

        // Mock the token as a contract with balance equal to global minimum
        vm.mockCall(
            otherToken,
            abi.encodeWithSelector(
                ERC20.balanceOf.selector,
                address(strategyWithAuctionTrigger)
            ),
            abi.encode(globalMinimum)
        );

        // Should use global minimum and since balance is not > minimum, goes through normal flow
        (bool shouldKick, bytes memory data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            otherToken
        );

        // Should go through normal flow since balance <= minimum, strategy returns true
        assertTrue(shouldKick);
        assertEq(
            data,
            abi.encodeWithSignature("kickAuction(address)", otherToken)
        );

        // Give strategy tokens more than global minimum
        vm.mockCall(
            otherToken,
            abi.encodeWithSelector(
                ERC20.balanceOf.selector,
                address(strategyWithAuctionTrigger)
            ),
            abi.encode(globalMinimum + 1)
        );

        (shouldKick, data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            otherToken
        );

        // Should return true with kickAuction since balance > minimum
        assertTrue(shouldKick);
        assertEq(
            data,
            abi.encodeCall(
                IAuctionSwapper(address(strategyWithAuctionTrigger))
                    .kickAuction,
                (otherToken)
            )
        );

        // Now set a specific minimum for this token that overrides global
        uint256 specificMinimum = 200e6;
        vm.prank(management);
        commonTrigger.setMinimumAmountToKick(
            address(strategyWithAuctionTrigger),
            otherToken,
            specificMinimum
        );

        // With balance = globalMinimum + 1 < specificMinimum, should go through normal flow
        (shouldKick, data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            otherToken
        );

        // Since balance (globalMinimum + 1) < specificMinimum, should use normal strategy trigger
        assertTrue(shouldKick);
        assertEq(
            data,
            abi.encodeWithSignature("kickAuction(address)", otherToken)
        );

        // Update balance to be > specific minimum
        vm.mockCall(
            otherToken,
            abi.encodeWithSelector(
                ERC20.balanceOf.selector,
                address(strategyWithAuctionTrigger)
            ),
            abi.encode(specificMinimum + 1)
        );

        (shouldKick, data) = commonTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            otherToken
        );

        // Should return true with kickAuction since balance > specific minimum
        assertTrue(shouldKick);
        assertEq(
            data,
            abi.encodeCall(
                IAuctionSwapper(address(strategyWithAuctionTrigger))
                    .kickAuction,
                (otherToken)
            )
        );
    }

    /*//////////////////////////////////////////////////////////////
                    LEGACY FALLBACK TESTS  
    //////////////////////////////////////////////////////////////*/

    function test_legacyFallbackForCustomTriggers() public {
        // Note: In production, LEGACY_REPORT_TRIGGER would be set to the deployed address
        // For testing, we would need to mock this behavior or deploy a legacy instance
        // This test demonstrates the intended functionality

        // The legacy fallback will check the LEGACY_REPORT_TRIGGER address
        // if local storage returns address(0)
        assertEq(
            commonTrigger.customStrategyTrigger(address(mockStrategy)),
            address(0)
        );

        // When LEGACY_REPORT_TRIGGER is set and has data, it would return that
        // For now, this test confirms the local storage works correctly
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
}
