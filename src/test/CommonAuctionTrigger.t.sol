// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, IStrategy, console, Roles} from "./utils/Setup.sol";
import {CommonAuctionTrigger, IBaseFee, ICustomAuctionTrigger, IStrategyAuctionTrigger} from "../AuctionTrigger/CommonAuctionTrigger.sol";
import {MockCustomAuctionTrigger, RevertingCustomTrigger} from "./mocks/MockCustomAuctionTrigger.sol";
import {MockStrategyWithAuctionTrigger} from "./mocks/MockStrategyWithAuctionTrigger.sol";

/**
 * @title CommonAuctionTrigger Test Suite
 * @dev Comprehensive test suite for the CommonAuctionTrigger contract covering
 *      core functionality, integration scenarios, and edge cases
 */
contract CommonAuctionTriggerTest is Setup {
    CommonAuctionTrigger public auctionTrigger;
    MockCustomAuctionTrigger public customAuctionTrigger;
    RevertingCustomTrigger public revertingCustomTrigger;
    MockStrategyWithAuctionTrigger public strategyWithAuctionTrigger;
    MockBaseFeeProvider public mockBaseFeeProvider;

    // Additional strategies for multi-strategy testing
    MockStrategyWithAuctionTrigger public strategy2;
    MockStrategyWithAuctionTrigger public strategy3;

    address public baseFeeProvider = 0xe0514dD71cfdC30147e76f65C30bdF60bfD437C3;
    address public fromToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

    // Events
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

        strategyWithAuctionTrigger = new MockStrategyWithAuctionTrigger(
            address(asset)
        );
        strategy2 = new MockStrategyWithAuctionTrigger(address(asset));
        strategy3 = new MockStrategyWithAuctionTrigger(address(asset));

        // Set up strategies
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
                        BASIC SETUP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setup() public {
        assertEq(auctionTrigger.governance(), address(daddy));
        assertEq(auctionTrigger.name(), "Yearn Common Auction Trigger");
        assertEq(auctionTrigger.baseFeeProvider(), address(0));
        assertEq(auctionTrigger.acceptableBaseFee(), 0);
        assertEq(
            auctionTrigger.customAuctionTrigger(address(mockStrategy)),
            address(0)
        );
        assertEq(
            auctionTrigger.customStrategyBaseFee(address(mockStrategy)),
            0
        );
    }

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_setBaseFeeProvider() public {
        vm.expectRevert("!governance");
        vm.prank(user);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);

        assertEq(auctionTrigger.baseFeeProvider(), address(0));

        vm.expectEmit(true, false, false, false);
        emit NewBaseFeeProvider(baseFeeProvider);

        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);

        assertEq(auctionTrigger.baseFeeProvider(), baseFeeProvider);
    }

    function test_setAcceptableBaseFee(uint256 _baseFee) public {
        vm.assume(_baseFee != 0 && _baseFee < type(uint256).max);

        vm.expectRevert("!governance");
        vm.prank(user);
        auctionTrigger.setAcceptableBaseFee(_baseFee);

        assertEq(auctionTrigger.acceptableBaseFee(), 0);

        vm.expectEmit(false, false, false, true);
        emit UpdatedAcceptableBaseFee(_baseFee);

        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(_baseFee);

        assertEq(auctionTrigger.acceptableBaseFee(), _baseFee);
    }

    function test_transferGovernance(
        address _caller,
        address _newGovernance
    ) public {
        vm.assume(_caller != daddy);
        vm.assume(_newGovernance != daddy && _newGovernance != address(0));

        assertEq(auctionTrigger.governance(), daddy);

        vm.expectRevert("!governance");
        vm.prank(_caller);
        auctionTrigger.transferGovernance(_newGovernance);

        assertEq(auctionTrigger.governance(), daddy);

        vm.expectRevert("ZERO ADDRESS");
        vm.prank(daddy);
        auctionTrigger.transferGovernance(address(0));

        assertEq(auctionTrigger.governance(), daddy);

        vm.prank(daddy);
        auctionTrigger.transferGovernance(_newGovernance);

        assertEq(auctionTrigger.governance(), _newGovernance);
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function test_setCustomAuctionTrigger() public {
        assertEq(
            auctionTrigger.customAuctionTrigger(address(mockStrategy)),
            address(0)
        );

        // Test unauthorized access
        vm.expectRevert("!authorized");
        vm.prank(user);
        auctionTrigger.setCustomAuctionTrigger(
            address(mockStrategy),
            address(customAuctionTrigger)
        );

        assertEq(
            auctionTrigger.customAuctionTrigger(address(mockStrategy)),
            address(0)
        );

        // Test authorized access by strategy management
        vm.expectEmit(true, true, false, false);
        emit UpdatedCustomAuctionTrigger(
            address(mockStrategy),
            address(customAuctionTrigger)
        );

        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(mockStrategy),
            address(customAuctionTrigger)
        );

        assertEq(
            auctionTrigger.customAuctionTrigger(address(mockStrategy)),
            address(customAuctionTrigger)
        );

        // Test resetting to zero address
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(mockStrategy),
            address(0)
        );

        assertEq(
            auctionTrigger.customAuctionTrigger(address(mockStrategy)),
            address(0)
        );
    }

    function test_setCustomStrategyBaseFee(uint256 _baseFee) public {
        vm.assume(_baseFee != 0);

        assertEq(
            auctionTrigger.customStrategyBaseFee(address(mockStrategy)),
            0
        );

        // Test unauthorized access
        vm.expectRevert("!authorized");
        vm.prank(user);
        auctionTrigger.setCustomStrategyBaseFee(
            address(mockStrategy),
            _baseFee
        );

        assertEq(
            auctionTrigger.customStrategyBaseFee(address(mockStrategy)),
            0
        );

        // Test authorized access by strategy management
        vm.expectEmit(true, false, false, true);
        emit UpdatedCustomStrategyBaseFee(address(mockStrategy), _baseFee);

        vm.prank(management);
        auctionTrigger.setCustomStrategyBaseFee(
            address(mockStrategy),
            _baseFee
        );

        assertEq(
            auctionTrigger.customStrategyBaseFee(address(mockStrategy)),
            _baseFee
        );
    }

    /*//////////////////////////////////////////////////////////////
                        BASE FEE FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    function test_getCurrentBaseFee() public {
        // Should return 0 when no provider is set
        assertEq(auctionTrigger.getCurrentBaseFee(), 0);

        // Set base fee provider
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);

        // Should return actual base fee
        uint256 currentBaseFee = IBaseFee(baseFeeProvider).basefee_global();
        assertEq(auctionTrigger.getCurrentBaseFee(), currentBaseFee);
    }

    function test_isCurrentBaseFeeAcceptable() public {
        // Should always return true when no provider is set
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());

        // Set base fee provider
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);

        uint256 currentBaseFee = IBaseFee(baseFeeProvider).basefee_global();

        // Should return false when acceptable base fee is lower than current
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(currentBaseFee / 2);
        assertFalse(auctionTrigger.isCurrentBaseFeeAcceptable());

        // Should return true when acceptable base fee is higher than current
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(currentBaseFee * 2);
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());
    }

    function test_baseFeeExactBoundaries() public {
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(mockBaseFeeProvider));

        uint256 testBaseFee = 50e9;
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

    /*//////////////////////////////////////////////////////////////
                        AUCTION TRIGGER CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    function test_auctionTrigger_withCustomTrigger() public {
        // Set custom trigger
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(mockStrategy),
            address(customAuctionTrigger)
        );

        // Test when custom trigger returns false
        customAuctionTrigger.setTriggerStatus(false);
        customAuctionTrigger.setTriggerData(bytes("Custom false"));

        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(mockStrategy),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Custom false"));

        // Test when custom trigger returns true
        customAuctionTrigger.setTriggerStatus(true);
        customAuctionTrigger.setTriggerData(bytes("Custom true"));

        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(mockStrategy),
            fromToken
        );
        assertTrue(shouldKick);
        assertEq(data, bytes("Custom true"));
    }

    function test_auctionTrigger_withRevertingCustomTrigger() public {
        // Set reverting custom trigger
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(mockStrategy),
            address(revertingCustomTrigger)
        );

        // When custom trigger reverts, it should fall back to default trigger logic
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(mockStrategy),
            fromToken
        );
        assertFalse(shouldKick);
        // Should get the message from default trigger since mockStrategy doesn't implement auctionTrigger
        assertEq(data, bytes("Strategy trigger not implemented or reverted"));
    }

    function test_auctionTrigger_customRevertsFallbackToStrategy() public {
        // Setup base fee to be acceptable
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);
        uint256 currentBaseFee = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(currentBaseFee * 2);

        // Set up strategy with auction trigger implementation
        strategyWithAuctionTrigger.setAuctionTriggerStatus(true);
        strategyWithAuctionTrigger.setAuctionTriggerData(
            bytes("Strategy fallback success")
        );

        // Set reverting custom trigger
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(revertingCustomTrigger)
        );

        // When custom trigger reverts, it should fall back to strategy's auctionTrigger
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertTrue(shouldKick);
        assertEq(data, bytes("Strategy fallback success"));
    }

    function test_auctionTrigger_customRevertsFallbackToStrategyWithBaseFeeRejection()
        public
    {
        // Setup base fee to be too high
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);
        uint256 currentBaseFee = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(currentBaseFee / 2); // Set lower than current

        // Set up strategy with auction trigger implementation
        strategyWithAuctionTrigger.setAuctionTriggerStatus(true);
        strategyWithAuctionTrigger.setAuctionTriggerData(
            bytes("Should not see this")
        );

        // Set reverting custom trigger
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(revertingCustomTrigger)
        );

        // When custom trigger reverts, fallback should be rejected due to base fee
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Base Fee"));
    }

    function test_auctionTrigger_customRevertsFallbackToRevertingStrategy()
        public
    {
        // Setup base fee to be acceptable
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);
        uint256 currentBaseFee = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(currentBaseFee * 2);

        // Set up strategy to revert on auction trigger
        strategyWithAuctionTrigger.setShouldRevertOnAuctionTrigger(true);

        // Set reverting custom trigger
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(revertingCustomTrigger)
        );

        // When both custom trigger and strategy trigger revert, should get default error message
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Strategy trigger not implemented or reverted"));
    }

    function test_auctionTrigger_configurableCustomTriggerFallback() public {
        // Setup base fee to be acceptable
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);
        uint256 currentBaseFee = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(currentBaseFee * 2);

        // Set up strategy with successful auction trigger
        strategyWithAuctionTrigger.setAuctionTriggerStatus(true);
        strategyWithAuctionTrigger.setAuctionTriggerData(
            bytes("Strategy success")
        );

        // Set up configurable custom trigger to work normally first
        customAuctionTrigger.setTriggerStatus(false);
        customAuctionTrigger.setTriggerData(bytes("Custom working"));
        customAuctionTrigger.setShouldRevert(false);

        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(customAuctionTrigger)
        );

        // First test: Custom trigger working normally
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Custom working"));

        // Second test: Make custom trigger revert, should fallback to strategy
        customAuctionTrigger.setShouldRevert(true);

        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertTrue(shouldKick);
        assertEq(data, bytes("Strategy success"));
    }

    function test_defaultAuctionTrigger_withBaseFeeCheck() public {
        // Set base fee provider and acceptable fee
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);

        uint256 currentBaseFee = IBaseFee(baseFeeProvider).basefee_global();

        // Test when base fee is too high
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(currentBaseFee / 2);

        (bool shouldKick, bytes memory data) = auctionTrigger
            .defaultAuctionTrigger(address(mockStrategy), fromToken);
        assertFalse(shouldKick);
        assertEq(data, bytes("Base Fee"));

        // Test when base fee is acceptable
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(currentBaseFee * 2);

        (shouldKick, data) = auctionTrigger.defaultAuctionTrigger(
            address(mockStrategy),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Strategy trigger not implemented or reverted"));
    }

    function test_defaultAuctionTrigger_withCustomStrategyBaseFee() public {
        // Set base fee provider and default acceptable fee
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);

        uint256 currentBaseFee = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(currentBaseFee / 2); // Too low

        // Should fail with default base fee
        (bool shouldKick, bytes memory data) = auctionTrigger
            .defaultAuctionTrigger(address(mockStrategy), fromToken);
        assertFalse(shouldKick);
        assertEq(data, bytes("Base Fee"));

        // Set custom strategy base fee that's acceptable
        vm.prank(management);
        auctionTrigger.setCustomStrategyBaseFee(
            address(mockStrategy),
            currentBaseFee * 2
        );

        // Should now pass base fee check
        (shouldKick, data) = auctionTrigger.defaultAuctionTrigger(
            address(mockStrategy),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Strategy trigger not implemented or reverted"));
    }

    function test_defaultAuctionTrigger_withStrategyImplementation() public {
        // Set acceptable base fee
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);
        uint256 currentBaseFee = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(currentBaseFee * 2);

        // Test with strategy that implements auction trigger
        strategyWithAuctionTrigger.setAuctionTriggerStatus(false);
        strategyWithAuctionTrigger.setAuctionTriggerData(
            bytes("Strategy false")
        );

        (bool shouldKick, bytes memory data) = auctionTrigger
            .defaultAuctionTrigger(
                address(strategyWithAuctionTrigger),
                fromToken
            );
        assertFalse(shouldKick);
        assertEq(data, bytes("Strategy false"));

        // Test when strategy returns true
        strategyWithAuctionTrigger.setAuctionTriggerStatus(true);
        strategyWithAuctionTrigger.setAuctionTriggerData(
            bytes("Strategy true")
        );

        (shouldKick, data) = auctionTrigger.defaultAuctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertTrue(shouldKick);
        assertEq(data, bytes("Strategy true"));
    }

    /*//////////////////////////////////////////////////////////////
                        INTEGRATION SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_multipleStrategiesWithDifferentConfigurations() public {
        // Setup base fee provider
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(mockBaseFeeProvider));
        mockBaseFeeProvider.setBaseFee(50e9);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(60e9);

        // Strategy 1: Uses default configuration
        strategyWithAuctionTrigger.setAuctionTriggerStatus(true);
        strategyWithAuctionTrigger.setAuctionTriggerData(bytes("Strategy1"));

        // Strategy 2: Uses custom base fee
        vm.prank(management);
        auctionTrigger.setCustomStrategyBaseFee(address(strategy2), 40e9); // Too restrictive
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

    /*//////////////////////////////////////////////////////////////
                        EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_auctionTrigger_noBaseFeeProvider() public {
        // Test that auction trigger works without base fee provider
        strategyWithAuctionTrigger.setAuctionTriggerStatus(true);
        strategyWithAuctionTrigger.setAuctionTriggerData(
            bytes("No base fee check")
        );

        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertTrue(shouldKick);
        assertEq(data, bytes("No base fee check"));
    }

    function test_extremeBaseFeeValues() public {
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(mockBaseFeeProvider));

        // Test with maximum base fee value
        mockBaseFeeProvider.setBaseFee(type(uint256).max);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(type(uint256).max);
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());

        // Test with minimum base fee value
        mockBaseFeeProvider.setBaseFee(0);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(0);
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZING TESTS
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

    function testFuzz_setCustomStrategyBaseFee(
        address _strategy,
        uint256 _baseFee
    ) public {
        vm.assume(_strategy != address(0));
        vm.assume(_baseFee > 0);
        // Assume _strategy is not a real contract to avoid management() calls succeeding
        vm.assume(_strategy.code.length == 0);

        // Should revert for unauthorized caller
        vm.expectRevert();
        vm.prank(user);
        auctionTrigger.setCustomStrategyBaseFee(_strategy, _baseFee);
    }
}

/*//////////////////////////////////////////////////////////////
                        MOCK CONTRACTS
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
