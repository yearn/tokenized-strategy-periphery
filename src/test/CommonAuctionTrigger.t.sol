// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, IStrategy, console, Roles} from "./utils/Setup.sol";

import {CommonAuctionTrigger, IBaseFee} from "../AuctionTrigger/CommonAuctionTrigger.sol";
import {MockCustomAuctionTrigger, RevertingCustomTrigger} from "./mocks/MockCustomAuctionTrigger.sol";
import {MockStrategyWithAuctionTrigger} from "./mocks/MockStrategyWithAuctionTrigger.sol";

contract CommonAuctionTriggerTest is Setup {
    CommonAuctionTrigger public auctionTrigger;
    MockCustomAuctionTrigger public customAuctionTrigger;
    RevertingCustomTrigger public revertingCustomTrigger;
    MockStrategyWithAuctionTrigger public strategyWithAuctionTrigger;

    address public baseFeeProvider = 0xe0514dD71cfdC30147e76f65C30bdF60bfD437C3;
    address public fromToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC

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
        strategyWithAuctionTrigger = new MockStrategyWithAuctionTrigger(
            address(asset)
        );

        // Set up the strategy with auction trigger using IStrategy interface
        IStrategy(address(strategyWithAuctionTrigger)).setKeeper(keeper);
        IStrategy(address(strategyWithAuctionTrigger))
            .setPerformanceFeeRecipient(performanceFeeRecipient);
        IStrategy(address(strategyWithAuctionTrigger)).setPendingManagement(
            management
        );
        vm.prank(management);
        IStrategy(address(strategyWithAuctionTrigger)).acceptManagement();
    }

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

        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(mockStrategy),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Custom trigger reverted"));
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

    function test_defaultAuctionTrigger_withRevertingStrategy() public {
        // Set acceptable base fee
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);
        uint256 currentBaseFee = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(currentBaseFee * 2);

        // Make strategy revert on auction trigger call
        strategyWithAuctionTrigger.setShouldRevertOnAuctionTrigger(true);

        (bool shouldKick, bytes memory data) = auctionTrigger
            .defaultAuctionTrigger(
                address(strategyWithAuctionTrigger),
                fromToken
            );
        assertFalse(shouldKick);
        assertEq(data, bytes("Strategy trigger not implemented or reverted"));
    }

    function test_auctionTrigger_fullIntegration() public {
        // Setup base fee
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);
        uint256 currentBaseFee = IBaseFee(baseFeeProvider).basefee_global();
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(currentBaseFee * 2);

        // Test without custom trigger (should use default)
        strategyWithAuctionTrigger.setAuctionTriggerStatus(true);
        strategyWithAuctionTrigger.setAuctionTriggerData(
            bytes("Default strategy")
        );

        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertTrue(shouldKick);
        assertEq(data, bytes("Default strategy"));

        // Set custom trigger and test it takes precedence
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategyWithAuctionTrigger),
            address(customAuctionTrigger)
        );

        customAuctionTrigger.setTriggerStatus(false);
        customAuctionTrigger.setTriggerData(bytes("Custom override"));

        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(strategyWithAuctionTrigger),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Custom override"));
    }

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

    function test_fuzz_setCustomStrategyBaseFee(
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

    function test_auctionTrigger_edgeCases() public {
        // Test with zero address should not revert due to try-catch
        // Note: This test covers edge cases where strategies don't implement the interface
        // The actual behavior may vary based on the specific address used due to EVM internals

        // Test that the function handles reverts gracefully with a mock strategy that doesn't implement auction trigger
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(mockStrategy),
            fromToken
        );

        // Should return false for strategies that don't implement the auction trigger interface
        assertFalse(shouldKick);
        assertEq(data, bytes("Strategy trigger not implemented or reverted"));
    }

    function test_eventEmissions() public {
        // Test NewBaseFeeProvider event
        vm.expectEmit(true, false, false, false);
        emit NewBaseFeeProvider(baseFeeProvider);
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(baseFeeProvider);

        // Test UpdatedAcceptableBaseFee event
        uint256 newBaseFee = 1000;
        vm.expectEmit(false, false, false, true);
        emit UpdatedAcceptableBaseFee(newBaseFee);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(newBaseFee);

        // Test UpdatedCustomAuctionTrigger event
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

        // Test UpdatedCustomStrategyBaseFee event
        uint256 customBaseFee = 2000;
        vm.expectEmit(true, false, false, true);
        emit UpdatedCustomStrategyBaseFee(address(mockStrategy), customBaseFee);
        vm.prank(management);
        auctionTrigger.setCustomStrategyBaseFee(
            address(mockStrategy),
            customBaseFee
        );
    }
}
