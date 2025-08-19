// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, IStrategy, console, Roles} from "./utils/Setup.sol";

import {CommonAuctionTrigger, IBaseFee} from "../AuctionTrigger/CommonAuctionTrigger.sol";
import {MockCustomAuctionTrigger, RevertingCustomTrigger} from "./mocks/MockCustomAuctionTrigger.sol";
import {MockStrategyWithAuctionTrigger} from "./mocks/MockStrategyWithAuctionTrigger.sol";

/**
 * @title Enhanced CommonAuctionTrigger Test Suite
 * @dev Comprehensive test suite covering edge cases, boundary conditions,
 *      integration scenarios, and stress testing for the CommonAuctionTrigger contract
 */
contract CommonAuctionTriggerEnhancedTest is Setup {
    CommonAuctionTrigger public auctionTrigger;
    MockCustomAuctionTrigger public customAuctionTrigger;
    RevertingCustomTrigger public revertingCustomTrigger;
    MockStrategyWithAuctionTrigger public strategyWithAuctionTrigger;
    MockStrategyWithAuctionTrigger public strategy2;
    MockStrategyWithAuctionTrigger public strategy3;

    // Mock base fee provider for testing
    MockBaseFeeProvider public mockBaseFeeProvider;

    address public fromToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC
    address public fromToken2 = 0xdAC17F958D2ee523a2206206994597C13D831ec7; // USDT

    // Test constants for boundary testing
    uint256 constant MAX_BASE_FEE = type(uint256).max;
    uint256 constant MIN_BASE_FEE = 1;
    uint256 constant MEDIUM_BASE_FEE = 50e9; // 50 gwei

    event NewBaseFeeProvider(address indexed provider);
    event UpdatedAcceptableBaseFee(uint256 acceptableBaseFee);
    event UpdatedCustomAuctionTrigger(
        address indexed strategy,
        address indexed trigger
    );
    event UpdatedCustomStrategyBaseFee(
        address indexed strategy,
        uint256 acceptableBaseFee
    );

    function setUp() public override {
        super.setUp();

        auctionTrigger = new CommonAuctionTrigger(daddy);
        customAuctionTrigger = new MockCustomAuctionTrigger();
        revertingCustomTrigger = new RevertingCustomTrigger();
        mockBaseFeeProvider = new MockBaseFeeProvider();

        // Set up multiple strategies for testing
        strategyWithAuctionTrigger = new MockStrategyWithAuctionTrigger(
            address(asset)
        );
        strategy2 = new MockStrategyWithAuctionTrigger(address(asset));
        strategy3 = new MockStrategyWithAuctionTrigger(address(asset));

        // Set up strategies with proper roles and management
        _setupStrategy(strategyWithAuctionTrigger);
        _setupStrategy(strategy2);
        _setupStrategy(strategy3);
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

    /*//////////////////////////////////////////////////////////////
                        BOUNDARY CONDITION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_extremeBaseFeeValues() public {
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(mockBaseFeeProvider));

        // Test with maximum base fee value
        mockBaseFeeProvider.setBaseFee(MAX_BASE_FEE);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(MAX_BASE_FEE);

        (bool shouldKick, bytes memory data) = auctionTrigger
            .defaultAuctionTrigger(
                address(strategyWithAuctionTrigger),
                fromToken
            );
        // Should pass base fee check but fail on strategy trigger
        assertFalse(shouldKick);
        assertEq(data, bytes("Strategy trigger not implemented or reverted"));

        // Test with minimum base fee value
        mockBaseFeeProvider.setBaseFee(MIN_BASE_FEE);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(0); // Should fail

        (shouldKick, data) = auctionTrigger.defaultAuctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Base Fee"));
    }

    function test_baseFeeExactBoundaries() public {
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(mockBaseFeeProvider));

        uint256 testBaseFee = MEDIUM_BASE_FEE;
        mockBaseFeeProvider.setBaseFee(testBaseFee);

        // Test exact match (should pass)
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(testBaseFee);
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());

        // Test one wei below (should fail)
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(testBaseFee - 1);
        assertFalse(auctionTrigger.isCurrentBaseFeeAcceptable());

        // Test one wei above (should pass)
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(testBaseFee + 1);
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());
    }

    function test_zeroBaseFeeScenarios() public {
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(mockBaseFeeProvider));

        // Test zero base fee from provider
        mockBaseFeeProvider.setBaseFee(0);

        // Any acceptable base fee should work with zero current base fee
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(100e9);
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());

        // Zero acceptable base fee should also work with zero current base fee
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(0);
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());
    }

    /*//////////////////////////////////////////////////////////////
                        STRESS TESTING
    //////////////////////////////////////////////////////////////*/

    function test_multipleStrategiesWithDifferentConfigurations() public {
        // Setup base fee provider
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(mockBaseFeeProvider));
        mockBaseFeeProvider.setBaseFee(MEDIUM_BASE_FEE);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(MEDIUM_BASE_FEE * 2);

        // Strategy 1: Uses default configuration
        strategyWithAuctionTrigger.setAuctionTriggerStatus(true);
        strategyWithAuctionTrigger.setAuctionTriggerData(bytes("Strategy1"));

        // Strategy 2: Uses custom base fee
        vm.prank(management);
        auctionTrigger.setCustomStrategyBaseFee(
            address(strategy2),
            MEDIUM_BASE_FEE / 2
        ); // Too restrictive
        strategy2.setAuctionTriggerStatus(true);
        strategy2.setAuctionTriggerData(bytes("Strategy2"));

        // Strategy 3: Uses custom trigger
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategy3),
            address(customAuctionTrigger)
        );
        customAuctionTrigger.setTriggerStatus(false);
        customAuctionTrigger.setTriggerData(bytes("CustomFalse"));

        // Test all strategies
        (bool shouldKick1, bytes memory data1) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertTrue(shouldKick1);
        assertEq(data1, bytes("Strategy1"));

        (bool shouldKick2, bytes memory data2) = auctionTrigger.auctionTrigger(
            address(strategy2),
            fromToken
        );
        assertFalse(shouldKick2);
        assertEq(data2, bytes("Base Fee"));

        (bool shouldKick3, bytes memory data3) = auctionTrigger.auctionTrigger(
            address(strategy3),
            fromToken
        );
        assertFalse(shouldKick3);
        assertEq(data3, bytes("CustomFalse"));
    }

    function test_bulkOperations() public {
        address[] memory strategies = new address[](3);
        strategies[0] = address(strategyWithAuctionTrigger);
        strategies[1] = address(strategy2);
        strategies[2] = address(strategy3);

        uint256[] memory baseFees = new uint256[](3);
        baseFees[0] = 10e9;
        baseFees[1] = 20e9;
        baseFees[2] = 30e9;

        // Set custom base fees for all strategies
        for (uint i = 0; i < strategies.length; i++) {
            vm.prank(management);
            auctionTrigger.setCustomStrategyBaseFee(strategies[i], baseFees[i]);
            assertEq(
                auctionTrigger.customStrategyBaseFee(strategies[i]),
                baseFees[i]
            );
        }

        // Reset all to zero
        for (uint i = 0; i < strategies.length; i++) {
            vm.prank(management);
            auctionTrigger.setCustomStrategyBaseFee(strategies[i], 0);
            assertEq(auctionTrigger.customStrategyBaseFee(strategies[i]), 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_complexWorkflowWithBaseFeeChanges() public {
        // Setup
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(mockBaseFeeProvider));
        strategyWithAuctionTrigger.setAuctionTriggerStatus(true);
        strategyWithAuctionTrigger.setAuctionTriggerData(bytes("WorkflowTest"));

        // Scenario 1: High base fee, restrictive acceptable fee
        mockBaseFeeProvider.setBaseFee(100e9);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(50e9);

        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Base Fee"));

        // Scenario 2: Same high base fee, but set custom strategy base fee
        vm.prank(management);
        auctionTrigger.setCustomStrategyBaseFee(
            address(strategyWithAuctionTrigger),
            150e9
        );

        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertTrue(shouldKick);
        assertEq(data, bytes("WorkflowTest"));

        // Scenario 3: Add custom trigger, should override base fee logic
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(customAuctionTrigger)
        );
        customAuctionTrigger.setTriggerStatus(false);
        customAuctionTrigger.setTriggerData(bytes("CustomOverride"));

        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("CustomOverride"));
    }

    function test_managementTransferScenario() public {
        address newManagement = address(99);

        // Set custom trigger as current management
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(customAuctionTrigger)
        );

        // Transfer strategy management
        vm.prank(management);
        IStrategy(address(strategyWithAuctionTrigger)).setPendingManagement(
            newManagement
        );
        vm.prank(newManagement);
        IStrategy(address(strategyWithAuctionTrigger)).acceptManagement();

        // Old management should no longer be able to modify
        vm.expectRevert("!authorized");
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(0)
        );

        // New management should be able to modify
        vm.prank(newManagement);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(0)
        );
        assertEq(
            auctionTrigger.customAuctionTrigger(
                address(strategyWithAuctionTrigger)
            ),
            address(0)
        );
    }

    /*//////////////////////////////////////////////////////////////
                        ERROR HANDLING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_customTriggerWithMaliciousContract() public {
        MaliciousCustomTrigger maliciousTrigger = new MaliciousCustomTrigger();

        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(maliciousTrigger)
        );

        // Should handle malicious reverts gracefully
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Custom trigger reverted"));
    }

    function test_baseFeeProviderFailure() public {
        FailingBaseFeeProvider failingProvider = new FailingBaseFeeProvider();

        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(failingProvider));

        // Should handle base fee provider failures gracefully
        // getCurrentBaseFee should revert when provider fails
        vm.expectRevert("Provider failed");
        auctionTrigger.getCurrentBaseFee();
    }

    function test_multipleTokenTypes() public {
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(mockBaseFeeProvider));
        mockBaseFeeProvider.setBaseFee(MEDIUM_BASE_FEE);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(MEDIUM_BASE_FEE * 2);

        strategyWithAuctionTrigger.setAuctionTriggerStatus(true);
        strategyWithAuctionTrigger.setAuctionTriggerData(bytes("MultiToken"));

        // Test with different token addresses
        address[] memory tokens = new address[](4);
        tokens[0] = fromToken; // USDC
        tokens[1] = fromToken2; // USDT
        tokens[2] = address(0); // Zero address
        tokens[3] = address(0xdeadbeef); // Random address

        for (uint i = 0; i < tokens.length; i++) {
            (bool shouldKick, bytes memory data) = auctionTrigger
                .auctionTrigger(address(strategyWithAuctionTrigger), tokens[i]);
            assertTrue(shouldKick);
            assertEq(data, bytes("MultiToken"));
        }
    }

    /*//////////////////////////////////////////////////////////////
                        STATE PERSISTENCE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_stateConsistencyAfterMultipleOperations() public {
        uint256 initialBaseFee = 25e9;

        // Initial setup
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(mockBaseFeeProvider));
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(initialBaseFee);

        // Verify initial state
        assertEq(auctionTrigger.acceptableBaseFee(), initialBaseFee);
        assertEq(
            auctionTrigger.baseFeeProvider(),
            address(mockBaseFeeProvider)
        );

        // Perform multiple state changes
        for (uint i = 1; i <= 5; i++) {
            uint256 newBaseFee = initialBaseFee * i;
            vm.prank(daddy);
            auctionTrigger.setAcceptableBaseFee(newBaseFee);
            assertEq(auctionTrigger.acceptableBaseFee(), newBaseFee);
        }

        // Set multiple custom strategy base fees
        address[] memory strategies = new address[](3);
        strategies[0] = address(strategyWithAuctionTrigger);
        strategies[1] = address(strategy2);
        strategies[2] = address(strategy3);

        for (uint i = 0; i < strategies.length; i++) {
            uint256 customFee = 10e9 * (i + 1);
            vm.prank(management);
            auctionTrigger.setCustomStrategyBaseFee(strategies[i], customFee);
            assertEq(
                auctionTrigger.customStrategyBaseFee(strategies[i]),
                customFee
            );
        }

        // Verify all states are still consistent
        for (uint i = 0; i < strategies.length; i++) {
            uint256 expectedFee = 10e9 * (i + 1);
            assertEq(
                auctionTrigger.customStrategyBaseFee(strategies[i]),
                expectedFee
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_governanceZeroAddressHandling() public {
        // The governance contract should have protection against zero address
        // but let's verify the behavior

        vm.expectRevert("ZERO ADDRESS");
        vm.prank(daddy);
        auctionTrigger.transferGovernance(address(0));
    }

    function test_governanceTransferAndRevert() public {
        address newGov = address(123);

        // Transfer governance
        vm.prank(daddy);
        auctionTrigger.transferGovernance(newGov);
        assertEq(auctionTrigger.governance(), newGov);

        // New governance should be able to set base fee
        vm.prank(newGov);
        auctionTrigger.setAcceptableBaseFee(100e9);
        assertEq(auctionTrigger.acceptableBaseFee(), 100e9);

        // Old governance should not be able to make changes
        vm.expectRevert("!governance");
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(200e9);
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZING ENHANCED TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_baseFeeComparisons(
        uint256 currentBaseFee,
        uint256 acceptableBaseFee
    ) public {
        vm.assume(currentBaseFee > 0);
        vm.assume(acceptableBaseFee > 0);

        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(mockBaseFeeProvider));
        mockBaseFeeProvider.setBaseFee(currentBaseFee);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(acceptableBaseFee);

        bool expected = currentBaseFee <= acceptableBaseFee;
        bool actual = auctionTrigger.isCurrentBaseFeeAcceptable();
        assertEq(actual, expected);
    }

    function testFuzz_customStrategyBaseFeeOverride(
        uint256 defaultBaseFee,
        uint256 customBaseFee,
        uint256 currentBaseFee
    ) public {
        vm.assume(defaultBaseFee > 0 && defaultBaseFee < type(uint128).max);
        vm.assume(customBaseFee > 0 && customBaseFee < type(uint128).max);
        vm.assume(currentBaseFee < type(uint128).max);

        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(mockBaseFeeProvider));
        mockBaseFeeProvider.setBaseFee(currentBaseFee);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(defaultBaseFee);

        // Set custom strategy base fee
        vm.prank(management);
        auctionTrigger.setCustomStrategyBaseFee(
            address(strategyWithAuctionTrigger),
            customBaseFee
        );

        // The custom base fee should be used instead of default
        (bool shouldKick, bytes memory data) = auctionTrigger
            .defaultAuctionTrigger(
                address(strategyWithAuctionTrigger),
                fromToken
            );

        if (currentBaseFee <= customBaseFee) {
            // Should pass base fee check but fail on strategy trigger
            assertFalse(shouldKick);
            assertEq(
                data,
                bytes("Strategy trigger not implemented or reverted")
            );
        } else {
            // Should fail base fee check
            assertFalse(shouldKick);
            assertEq(data, bytes("Base Fee"));
        }
    }

    /*//////////////////////////////////////////////////////////////
                        GAS OPTIMIZATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_gasUsageComparison() public {
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(mockBaseFeeProvider));
        mockBaseFeeProvider.setBaseFee(MEDIUM_BASE_FEE);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(MEDIUM_BASE_FEE * 2);

        strategyWithAuctionTrigger.setAuctionTriggerStatus(true);
        strategyWithAuctionTrigger.setAuctionTriggerData(bytes("GasTest"));

        // Measure gas for default trigger
        uint256 gasBefore = gasleft();
        auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        uint256 gasUsedDefault = gasBefore - gasleft();

        // Set custom trigger and measure gas
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(customAuctionTrigger)
        );
        customAuctionTrigger.setTriggerStatus(true);
        customAuctionTrigger.setTriggerData(bytes("GasTest"));

        gasBefore = gasleft();
        auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        uint256 gasUsedCustom = gasBefore - gasleft();

        // Log gas usage for comparison
        console.log("Gas used for default trigger:", gasUsedDefault);
        console.log("Gas used for custom trigger:", gasUsedCustom);

        // Custom trigger should use less gas as it skips strategy call
        assertLt(gasUsedCustom, gasUsedDefault);
    }
}

/*//////////////////////////////////////////////////////////////
                        HELPER CONTRACTS
//////////////////////////////////////////////////////////////*/

contract MockBaseFeeProvider is IBaseFee {
    uint256 private _baseFee;

    function setBaseFee(uint256 baseFee) external {
        _baseFee = baseFee;
    }

    function basefee_global() external view returns (uint256) {
        return _baseFee;
    }
}

contract MaliciousCustomTrigger {
    function auctionTrigger(
        address,
        address
    ) external pure returns (bool, bytes memory) {
        revert(
            "Malicious revert with long error message that could potentially cause issues"
        );
    }
}

contract FailingBaseFeeProvider is IBaseFee {
    function basefee_global() external pure returns (uint256) {
        revert("Provider failed");
    }
}
