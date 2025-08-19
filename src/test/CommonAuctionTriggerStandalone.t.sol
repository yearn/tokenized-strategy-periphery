// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/Test.sol";
import {CommonAuctionTrigger, IBaseFee, ICustomAuctionTrigger} from "../AuctionTrigger/CommonAuctionTrigger.sol";

/**
 * @title Standalone CommonAuctionTrigger Test Suite
 * @dev Minimal test suite that doesn't depend on complex setup infrastructure
 */
contract CommonAuctionTriggerStandaloneTest is Test {
    CommonAuctionTrigger public auctionTrigger;
    MockBaseFeeProvider public baseFeeProvider;
    MockStrategy public strategy;
    MockCustomTrigger public customTrigger;

    address public governance = address(0x1);
    address public management = address(0x2);
    address public attacker = address(0x666);
    address public fromToken = address(0x3);

    function setUp() public {
        auctionTrigger = new CommonAuctionTrigger(governance);
        baseFeeProvider = new MockBaseFeeProvider();
        strategy = new MockStrategy(management);
        customTrigger = new MockCustomTrigger();
    }

    /*//////////////////////////////////////////////////////////////
                        BASIC FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_initialState() public {
        assertEq(auctionTrigger.governance(), governance);
        assertEq(auctionTrigger.name(), "Yearn Common Auction Trigger");
        assertEq(auctionTrigger.baseFeeProvider(), address(0));
        assertEq(auctionTrigger.acceptableBaseFee(), 0);
        assertEq(
            auctionTrigger.customAuctionTrigger(address(strategy)),
            address(0)
        );
        assertEq(auctionTrigger.customStrategyBaseFee(address(strategy)), 0);
    }

    function test_setBaseFeeProvider() public {
        // Only governance can set
        vm.expectRevert("!governance");
        vm.prank(attacker);
        auctionTrigger.setBaseFeeProvider(address(baseFeeProvider));

        // Governance can set
        vm.prank(governance);
        auctionTrigger.setBaseFeeProvider(address(baseFeeProvider));
        assertEq(auctionTrigger.baseFeeProvider(), address(baseFeeProvider));
    }

    function test_setAcceptableBaseFee() public {
        uint256 newBaseFee = 50e9;

        // Only governance can set
        vm.expectRevert("!governance");
        vm.prank(attacker);
        auctionTrigger.setAcceptableBaseFee(newBaseFee);

        // Governance can set
        vm.prank(governance);
        auctionTrigger.setAcceptableBaseFee(newBaseFee);
        assertEq(auctionTrigger.acceptableBaseFee(), newBaseFee);
    }

    function test_setCustomAuctionTrigger() public {
        // Only strategy management can set
        vm.expectRevert("!authorized");
        vm.prank(attacker);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategy),
            address(customTrigger)
        );

        // Strategy management can set
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategy),
            address(customTrigger)
        );
        assertEq(
            auctionTrigger.customAuctionTrigger(address(strategy)),
            address(customTrigger)
        );
    }

    function test_setCustomStrategyBaseFee() public {
        uint256 customBaseFee = 75e9;

        // Only strategy management can set
        vm.expectRevert("!authorized");
        vm.prank(attacker);
        auctionTrigger.setCustomStrategyBaseFee(
            address(strategy),
            customBaseFee
        );

        // Strategy management can set
        vm.prank(management);
        auctionTrigger.setCustomStrategyBaseFee(
            address(strategy),
            customBaseFee
        );
        assertEq(
            auctionTrigger.customStrategyBaseFee(address(strategy)),
            customBaseFee
        );
    }

    /*//////////////////////////////////////////////////////////////
                        BASE FEE FUNCTIONALITY
    //////////////////////////////////////////////////////////////*/

    function test_getCurrentBaseFee() public {
        // Should return 0 when no provider is set
        assertEq(auctionTrigger.getCurrentBaseFee(), 0);

        // Set provider and test
        vm.prank(governance);
        auctionTrigger.setBaseFeeProvider(address(baseFeeProvider));

        uint256 testBaseFee = 30e9;
        baseFeeProvider.setBaseFee(testBaseFee);
        assertEq(auctionTrigger.getCurrentBaseFee(), testBaseFee);
    }

    function test_isCurrentBaseFeeAcceptable() public {
        // Should always return true when no provider is set
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());

        // Set provider and test
        vm.prank(governance);
        auctionTrigger.setBaseFeeProvider(address(baseFeeProvider));

        uint256 currentBaseFee = 40e9;
        baseFeeProvider.setBaseFee(currentBaseFee);

        // Test with acceptable base fee higher than current
        vm.prank(governance);
        auctionTrigger.setAcceptableBaseFee(50e9);
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());

        // Test with acceptable base fee lower than current
        vm.prank(governance);
        auctionTrigger.setAcceptableBaseFee(30e9);
        assertFalse(auctionTrigger.isCurrentBaseFeeAcceptable());
    }

    /*//////////////////////////////////////////////////////////////
                        AUCTION TRIGGER LOGIC
    //////////////////////////////////////////////////////////////*/

    function test_auctionTrigger_withCustomTrigger() public {
        // Set custom trigger
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategy),
            address(customTrigger)
        );

        // Test when custom trigger returns false
        customTrigger.setTriggerStatus(false);
        customTrigger.setTriggerData(bytes("Custom false"));

        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategy),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Custom false"));

        // Test when custom trigger returns true
        customTrigger.setTriggerStatus(true);
        customTrigger.setTriggerData(bytes("Custom true"));

        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(strategy),
            fromToken
        );
        assertTrue(shouldKick);
        assertEq(data, bytes("Custom true"));
    }

    function test_defaultAuctionTrigger_baseFeeCheck() public {
        // Set base fee provider
        vm.prank(governance);
        auctionTrigger.setBaseFeeProvider(address(baseFeeProvider));

        uint256 currentBaseFee = 40e9;
        baseFeeProvider.setBaseFee(currentBaseFee);

        // Test when base fee is too high
        vm.prank(governance);
        auctionTrigger.setAcceptableBaseFee(30e9);

        (bool shouldKick, bytes memory data) = auctionTrigger
            .defaultAuctionTrigger(address(strategy), fromToken);
        assertFalse(shouldKick);
        assertEq(data, bytes("Base Fee"));

        // Test when base fee is acceptable
        vm.prank(governance);
        auctionTrigger.setAcceptableBaseFee(50e9);

        (shouldKick, data) = auctionTrigger.defaultAuctionTrigger(
            address(strategy),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Strategy trigger not implemented or reverted"));
    }

    function test_defaultAuctionTrigger_customStrategyBaseFee() public {
        // Set base fee provider
        vm.prank(governance);
        auctionTrigger.setBaseFeeProvider(address(baseFeeProvider));

        uint256 currentBaseFee = 40e9;
        baseFeeProvider.setBaseFee(currentBaseFee);

        // Set default acceptable base fee too low
        vm.prank(governance);
        auctionTrigger.setAcceptableBaseFee(30e9);

        // Should fail with default base fee
        (bool shouldKick, bytes memory data) = auctionTrigger
            .defaultAuctionTrigger(address(strategy), fromToken);
        assertFalse(shouldKick);
        assertEq(data, bytes("Base Fee"));

        // Set custom strategy base fee that's acceptable
        vm.prank(management);
        auctionTrigger.setCustomStrategyBaseFee(address(strategy), 50e9);

        // Should now pass base fee check
        (shouldKick, data) = auctionTrigger.defaultAuctionTrigger(
            address(strategy),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Strategy trigger not implemented or reverted"));
    }

    /*//////////////////////////////////////////////////////////////
                        BOUNDARY CONDITION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_extremeBaseFeeValues() public {
        vm.prank(governance);
        auctionTrigger.setBaseFeeProvider(address(baseFeeProvider));

        // Test with maximum base fee value
        baseFeeProvider.setBaseFee(type(uint256).max);
        vm.prank(governance);
        auctionTrigger.setAcceptableBaseFee(type(uint256).max);
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());

        // Test with minimum base fee value
        baseFeeProvider.setBaseFee(0);
        vm.prank(governance);
        auctionTrigger.setAcceptableBaseFee(0);
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());
    }

    function test_exactBoundaryConditions() public {
        vm.prank(governance);
        auctionTrigger.setBaseFeeProvider(address(baseFeeProvider));

        uint256 testBaseFee = 50e9;
        baseFeeProvider.setBaseFee(testBaseFee);

        // Test exact match (should pass)
        vm.prank(governance);
        auctionTrigger.setAcceptableBaseFee(testBaseFee);
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());

        // Test one wei below (should fail)
        vm.prank(governance);
        auctionTrigger.setAcceptableBaseFee(testBaseFee - 1);
        assertFalse(auctionTrigger.isCurrentBaseFeeAcceptable());

        // Test one wei above (should pass)
        vm.prank(governance);
        auctionTrigger.setAcceptableBaseFee(testBaseFee + 1);
        assertTrue(auctionTrigger.isCurrentBaseFeeAcceptable());
    }

    /*//////////////////////////////////////////////////////////////
                        ERROR HANDLING TESTS
    //////////////////////////////////////////////////////////////*/

    function test_customTriggerReverts() public {
        RevertingCustomTrigger revertingTrigger = new RevertingCustomTrigger();

        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategy),
            address(revertingTrigger)
        );

        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategy),
            fromToken
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Custom trigger reverted"));
    }

    function test_baseFeeProviderReverts() public {
        RevertingBaseFeeProvider revertingProvider = new RevertingBaseFeeProvider();

        vm.prank(governance);
        auctionTrigger.setBaseFeeProvider(address(revertingProvider));

        // Should handle provider failures gracefully
        vm.expectRevert("Provider failed");
        auctionTrigger.getCurrentBaseFee();
    }

    /*//////////////////////////////////////////////////////////////
                        FUZZING TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_baseFeeComparisons(
        uint128 currentBaseFee,
        uint128 acceptableBaseFee
    ) public {
        vm.assume(currentBaseFee > 0);
        vm.assume(acceptableBaseFee > 0);

        vm.prank(governance);
        auctionTrigger.setBaseFeeProvider(address(baseFeeProvider));
        baseFeeProvider.setBaseFee(currentBaseFee);
        vm.prank(governance);
        auctionTrigger.setAcceptableBaseFee(acceptableBaseFee);

        bool expected = currentBaseFee <= acceptableBaseFee;
        bool actual = auctionTrigger.isCurrentBaseFeeAcceptable();
        assertEq(actual, expected);
    }

    function testFuzz_customBaseFeeOverride(
        uint128 defaultBaseFee,
        uint128 customBaseFee,
        uint128 currentBaseFee
    ) public {
        vm.assume(defaultBaseFee > 0);
        vm.assume(customBaseFee > 0);

        vm.prank(governance);
        auctionTrigger.setBaseFeeProvider(address(baseFeeProvider));
        baseFeeProvider.setBaseFee(currentBaseFee);
        vm.prank(governance);
        auctionTrigger.setAcceptableBaseFee(defaultBaseFee);

        // Set custom strategy base fee
        vm.prank(management);
        auctionTrigger.setCustomStrategyBaseFee(
            address(strategy),
            customBaseFee
        );

        // The custom base fee should be used instead of default
        (bool shouldKick, bytes memory data) = auctionTrigger
            .defaultAuctionTrigger(address(strategy), fromToken);

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

contract MockStrategy {
    address public management;

    constructor(address _management) {
        management = _management;
    }
}

contract MockCustomTrigger is ICustomAuctionTrigger {
    bool public triggerStatus;
    bytes public triggerData;

    function auctionTrigger(
        address,
        address
    ) external view override returns (bool, bytes memory) {
        return (triggerStatus, triggerData);
    }

    function setTriggerStatus(bool _status) external {
        triggerStatus = _status;
    }

    function setTriggerData(bytes calldata _data) external {
        triggerData = _data;
    }
}

contract RevertingCustomTrigger is ICustomAuctionTrigger {
    function auctionTrigger(
        address,
        address
    ) external pure override returns (bool, bytes memory) {
        revert("Always reverts");
    }
}

contract RevertingBaseFeeProvider is IBaseFee {
    function basefee_global() external pure returns (uint256) {
        revert("Provider failed");
    }
}
