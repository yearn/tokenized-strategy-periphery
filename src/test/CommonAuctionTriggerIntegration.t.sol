// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, IStrategy, console, Roles} from "./utils/Setup.sol";
import {CommonAuctionTrigger, IBaseFee, ICustomAuctionTrigger, IStrategyAuctionTrigger} from "../AuctionTrigger/CommonAuctionTrigger.sol";
import {MockCustomAuctionTrigger} from "./mocks/MockCustomAuctionTrigger.sol";
import {MockStrategyWithAuctionTrigger} from "./mocks/MockStrategyWithAuctionTrigger.sol";

/**
 * @title Integration-focused CommonAuctionTrigger Test Suite
 * @dev This test suite focuses on real-world integration scenarios,
 *      cross-contract interactions, and end-to-end workflows
 */
contract CommonAuctionTriggerIntegrationTest is Setup {
    CommonAuctionTrigger public auctionTrigger;
    MockCustomAuctionTrigger public customTrigger1;
    MockCustomAuctionTrigger public customTrigger2;
    MockBaseFeeProvider public baseFeeProvider;

    // Multiple strategies for integration testing
    MockStrategyWithAuctionTrigger[] public strategies;

    // Real-world token addresses for integration
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    // Keeper network simulation
    address public keeper1 = address(0x1001);
    address public keeper2 = address(0x1002);
    address public keeper3 = address(0x1003);

    event AuctionKicked(
        address indexed strategy,
        address indexed token,
        bool success
    );

    function setUp() public override {
        super.setUp();

        auctionTrigger = new CommonAuctionTrigger(daddy);
        customTrigger1 = new MockCustomAuctionTrigger();
        customTrigger2 = new MockCustomAuctionTrigger();
        baseFeeProvider = new MockBaseFeeProvider();

        // Set up base fee provider
        vm.prank(daddy);
        auctionTrigger.setBaseFeeProvider(address(baseFeeProvider));

        // Deploy multiple strategies for testing
        for (uint i = 0; i < 5; i++) {
            MockStrategyWithAuctionTrigger strategy = new MockStrategyWithAuctionTrigger(
                    address(asset)
                );
            _setupStrategy(strategy, i);
            strategies.push(strategy);
        }
    }

    function _setupStrategy(
        MockStrategyWithAuctionTrigger strategy,
        uint256 id
    ) internal {
        IStrategy(address(strategy)).setKeeper(keeper);
        IStrategy(address(strategy)).setPerformanceFeeRecipient(
            performanceFeeRecipient
        );
        IStrategy(address(strategy)).setPendingManagement(management);
        vm.prank(management);
        IStrategy(address(strategy)).acceptManagement();

        // Configure strategy auction trigger
        strategy.setAuctionTriggerStatus(true);
        strategy.setAuctionTriggerData(abi.encode("Strategy", id, "auction"));

        vm.label(
            address(strategy),
            string(abi.encodePacked("Strategy", _toString(id)))
        );
    }

    /*//////////////////////////////////////////////////////////////
                        MULTI-STRATEGY SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_multiStrategyAuctionCoordination() public {
        // Setup different configurations for each strategy
        _setupDiverseStrategyConfigurations();

        // Simulate keeper checking all strategies
        bool[] memory shouldKickResults = new bool[](strategies.length);
        bytes[] memory dataResults = new bytes[](strategies.length);

        for (uint i = 0; i < strategies.length; i++) {
            (shouldKickResults[i], dataResults[i]) = auctionTrigger
                .auctionTrigger(address(strategies[i]), USDC);
        }

        // Verify results match expected configurations
        assertTrue(shouldKickResults[0]); // Default config, should work
        assertFalse(shouldKickResults[1]); // Custom trigger disabled
        assertTrue(shouldKickResults[2]); // Custom trigger enabled
        assertFalse(shouldKickResults[3]); // High base fee threshold
        assertTrue(shouldKickResults[4]); // Low base fee threshold
    }

    function test_keeperNetworkSimulation() public {
        baseFeeProvider.setBaseFee(25e9);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(30e9);

        // Configure strategies
        for (uint i = 0; i < strategies.length; i++) {
            strategies[i].setAuctionTriggerStatus(i % 2 == 0); // Alternate true/false
        }

        // Simulate multiple keepers checking triggers
        address[] memory keepers = new address[](3);
        keepers[0] = keeper1;
        keepers[1] = keeper2;
        keepers[2] = keeper3;

        for (uint k = 0; k < keepers.length; k++) {
            for (uint s = 0; s < strategies.length; s++) {
                vm.prank(keepers[k]);
                (bool shouldKick, bytes memory data) = auctionTrigger
                    .auctionTrigger(address(strategies[s]), USDC);

                // Results should be consistent across keepers
                if (s % 2 == 0) {
                    assertTrue(shouldKick);
                } else {
                    assertFalse(shouldKick);
                }
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        REAL-WORLD TOKEN SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_multiTokenAuctionTriggers() public {
        address[] memory tokens = new address[](4);
        tokens[0] = WETH;
        tokens[1] = USDC;
        tokens[2] = USDT;
        tokens[3] = DAI;

        // Configure strategy to be ready for auctions
        baseFeeProvider.setBaseFee(20e9);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(25e9);
        strategies[0].setAuctionTriggerStatus(true);

        // Test auction triggers for different tokens
        for (uint i = 0; i < tokens.length; i++) {
            strategies[0].setAuctionTriggerData(
                abi.encode("Token", tokens[i], "ready")
            );

            (bool shouldKick, bytes memory data) = auctionTrigger
                .auctionTrigger(address(strategies[0]), tokens[i]);

            assertTrue(shouldKick);
            // Verify data contains token information
            assertEq(data, abi.encode("Token", tokens[i], "ready"));
        }
    }

    /*//////////////////////////////////////////////////////////////
                        DYNAMIC CONFIGURATION SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_dynamicConfigurationChanges() public {
        MockStrategyWithAuctionTrigger strategy = strategies[0];

        // Initial configuration: use default settings
        baseFeeProvider.setBaseFee(30e9);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(25e9); // Base fee too high
        strategy.setAuctionTriggerStatus(true);

        // Should fail due to high base fee
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategy),
            USDC
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Base Fee"));

        // Management sets custom base fee
        vm.prank(management);
        auctionTrigger.setCustomStrategyBaseFee(address(strategy), 35e9);

        // Should now pass
        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(strategy),
            USDC
        );
        assertTrue(shouldKick);

        // Management switches to custom trigger
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategy),
            address(customTrigger1)
        );
        customTrigger1.setTriggerStatus(false);
        customTrigger1.setTriggerData(bytes("Custom disabled"));

        // Should now use custom trigger
        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(strategy),
            USDC
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Custom disabled"));

        // Enable custom trigger
        customTrigger1.setTriggerStatus(true);
        customTrigger1.setTriggerData(bytes("Custom enabled"));

        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(strategy),
            USDC
        );
        assertTrue(shouldKick);
        assertEq(data, bytes("Custom enabled"));
    }

    /*//////////////////////////////////////////////////////////////
                        NETWORK CONDITION SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_varyingNetworkConditions() public {
        MockStrategyWithAuctionTrigger strategy = strategies[0];
        strategy.setAuctionTriggerStatus(true);
        strategy.setAuctionTriggerData(bytes("Network test"));

        // Test different network conditions
        uint256[] memory networkBaseFees = new uint256[](6);
        networkBaseFees[0] = 1e9; // 1 gwei - very low
        networkBaseFees[1] = 10e9; // 10 gwei - low
        networkBaseFees[2] = 30e9; // 30 gwei - medium
        networkBaseFees[3] = 100e9; // 100 gwei - high
        networkBaseFees[4] = 500e9; // 500 gwei - very high
        networkBaseFees[5] = 1000e9; // 1000 gwei - extreme

        uint256 acceptableBaseFee = 50e9; // 50 gwei threshold
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(acceptableBaseFee);

        for (uint i = 0; i < networkBaseFees.length; i++) {
            baseFeeProvider.setBaseFee(networkBaseFees[i]);

            (bool shouldKick, bytes memory data) = auctionTrigger
                .auctionTrigger(address(strategy), USDC);

            if (networkBaseFees[i] <= acceptableBaseFee) {
                assertTrue(
                    shouldKick,
                    string(
                        abi.encodePacked(
                            "Should kick at ",
                            _toString(networkBaseFees[i])
                        )
                    )
                );
                assertEq(data, bytes("Network test"));
            } else {
                assertFalse(
                    shouldKick,
                    string(
                        abi.encodePacked(
                            "Should not kick at ",
                            _toString(networkBaseFees[i])
                        )
                    )
                );
                assertEq(data, bytes("Base Fee"));
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY LIFECYCLE SCENARIOS
    //////////////////////////////////////////////////////////////*/

    function test_strategyLifecycleIntegration() public {
        MockStrategyWithAuctionTrigger strategy = strategies[0];

        // Phase 1: Strategy deployment and initial configuration
        strategy.setAuctionTriggerStatus(false); // Not ready yet
        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategy),
            USDC
        );
        assertFalse(shouldKick);

        // Phase 2: Strategy becomes active
        strategy.setAuctionTriggerStatus(true);
        strategy.setAuctionTriggerData(bytes("Phase 2: Active"));
        baseFeeProvider.setBaseFee(20e9);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(25e9);

        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(strategy),
            USDC
        );
        assertTrue(shouldKick);
        assertEq(data, bytes("Phase 2: Active"));

        // Phase 3: Management wants custom control
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategy),
            address(customTrigger1)
        );
        customTrigger1.setTriggerStatus(true);
        customTrigger1.setTriggerData(bytes("Phase 3: Custom"));

        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(strategy),
            USDC
        );
        assertTrue(shouldKick);
        assertEq(data, bytes("Phase 3: Custom"));

        // Phase 4: Strategy becomes inactive
        customTrigger1.setTriggerStatus(false);
        customTrigger1.setTriggerData(bytes("Phase 4: Inactive"));

        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(strategy),
            USDC
        );
        assertFalse(shouldKick);
        assertEq(data, bytes("Phase 4: Inactive"));

        // Phase 5: Return to default configuration
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(address(strategy), address(0));
        strategy.setAuctionTriggerStatus(true);
        strategy.setAuctionTriggerData(bytes("Phase 5: Default"));

        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(strategy),
            USDC
        );
        assertTrue(shouldKick);
        assertEq(data, bytes("Phase 5: Default"));
    }

    /*//////////////////////////////////////////////////////////////
                        CROSS-CONTRACT INTEGRATION
    //////////////////////////////////////////////////////////////*/

    function test_integrationWithExternalContracts() public {
        // Deploy a complex custom trigger that interacts with other contracts
        ComplexCustomTrigger complexTrigger = new ComplexCustomTrigger(
            address(baseFeeProvider)
        );

        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategies[0]),
            address(complexTrigger)
        );

        // Configure complex conditions
        baseFeeProvider.setBaseFee(30e9);
        complexTrigger.setMinBaseFee(25e9);
        complexTrigger.setMaxBaseFee(35e9);
        complexTrigger.setAdditionalCheck(true);

        (bool shouldKick, bytes memory data) = auctionTrigger.auctionTrigger(
            address(strategies[0]),
            USDC
        );
        assertTrue(shouldKick);

        // Change conditions to make it fail
        complexTrigger.setAdditionalCheck(false);
        (shouldKick, data) = auctionTrigger.auctionTrigger(
            address(strategies[0]),
            USDC
        );
        assertFalse(shouldKick);
    }

    /*//////////////////////////////////////////////////////////////
                        PERFORMANCE AND OPTIMIZATION
    //////////////////////////////////////////////////////////////*/

    function test_batchAuctionTriggerChecks() public {
        // Setup all strategies to be ready
        baseFeeProvider.setBaseFee(20e9);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(25e9);

        for (uint i = 0; i < strategies.length; i++) {
            strategies[i].setAuctionTriggerStatus(true);
            strategies[i].setAuctionTriggerData(abi.encode("Batch", i));
        }

        // Simulate batch checking by a keeper
        bool[] memory results = new bool[](strategies.length);
        bytes[] memory dataArray = new bytes[](strategies.length);

        uint256 gasStart = gasleft();
        for (uint i = 0; i < strategies.length; i++) {
            (results[i], dataArray[i]) = auctionTrigger.auctionTrigger(
                address(strategies[i]),
                USDC
            );
        }
        uint256 gasUsed = gasStart - gasleft();

        // Verify all succeeded
        for (uint i = 0; i < strategies.length; i++) {
            assertTrue(results[i]);
            assertEq(dataArray[i], abi.encode("Batch", i));
        }

        console.log(
            "Gas used for",
            strategies.length,
            "auction trigger checks:",
            gasUsed
        );
        console.log("Average gas per check:", gasUsed / strategies.length);
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _setupDiverseStrategyConfigurations() internal {
        baseFeeProvider.setBaseFee(25e9);
        vm.prank(daddy);
        auctionTrigger.setAcceptableBaseFee(30e9);

        // Strategy 0: Default configuration (should work)
        strategies[0].setAuctionTriggerStatus(true);
        strategies[0].setAuctionTriggerData(bytes("Default config"));

        // Strategy 1: Custom trigger disabled
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategies[1]),
            address(customTrigger1)
        );
        customTrigger1.setTriggerStatus(false);
        customTrigger1.setTriggerData(bytes("Custom disabled"));

        // Strategy 2: Custom trigger enabled
        vm.prank(management);
        auctionTrigger.setCustomAuctionTrigger(
            address(strategies[2]),
            address(customTrigger2)
        );
        customTrigger2.setTriggerStatus(true);
        customTrigger2.setTriggerData(bytes("Custom enabled"));

        // Strategy 3: Custom high base fee threshold (should fail)
        vm.prank(management);
        auctionTrigger.setCustomStrategyBaseFee(address(strategies[3]), 20e9);
        strategies[3].setAuctionTriggerStatus(true);

        // Strategy 4: Custom low base fee threshold (should work)
        vm.prank(management);
        auctionTrigger.setCustomStrategyBaseFee(address(strategies[4]), 50e9);
        strategies[4].setAuctionTriggerStatus(true);
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";

        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }

        return string(buffer);
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

contract ComplexCustomTrigger is ICustomAuctionTrigger {
    IBaseFee public baseFeeProvider;
    uint256 public minBaseFee;
    uint256 public maxBaseFee;
    bool public additionalCheck;

    constructor(address _baseFeeProvider) {
        baseFeeProvider = IBaseFee(_baseFeeProvider);
    }

    function setMinBaseFee(uint256 _min) external {
        minBaseFee = _min;
    }

    function setMaxBaseFee(uint256 _max) external {
        maxBaseFee = _max;
    }

    function setAdditionalCheck(bool _check) external {
        additionalCheck = _check;
    }

    function auctionTrigger(
        address,
        address
    ) external view override returns (bool, bytes memory) {
        uint256 currentBaseFee = baseFeeProvider.basefee_global();

        // Complex logic combining multiple conditions
        bool baseFeeCheck = currentBaseFee >= minBaseFee &&
            currentBaseFee <= maxBaseFee;
        bool shouldTrigger = baseFeeCheck && additionalCheck;

        bytes memory data = abi.encode(
            "Complex trigger",
            currentBaseFee,
            baseFeeCheck,
            additionalCheck,
            shouldTrigger
        );

        return (shouldTrigger, data);
    }
}
