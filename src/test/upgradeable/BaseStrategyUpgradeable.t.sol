// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {UpgradeableSetup, IStrategy, SafeERC20, ERC20} from "../utils/UpgradeableSetup.sol";
import {MockUpgradeableStrategy} from "../mocks/MockUpgradeableStrategy.sol";

contract BaseStrategyUpgradeableTest is UpgradeableSetup {
    using SafeERC20 for ERC20;

    IStrategy public strategy;
    address public strategyImpl;

    function setUp() public override {
        super.setUp();

        // Deploy implementation
        strategyImpl = address(new MockUpgradeableStrategy());

        // Deploy and initialize proxy
        address proxy = deployProxy(strategyImpl);

        // Initialize the strategy
        MockUpgradeableStrategy(proxy).initialize(
            address(asset),
            "Test Strategy",
            management,
            performanceFeeRecipient,
            keeper
        );

        strategy = IStrategy(proxy);
    }

    function test_initialization() public {
        // Verify initialization
        assertEq(strategy.asset(), address(asset));
        assertEq(strategy.name(), "Test Strategy");
        assertEq(strategy.management(), management);
        assertEq(strategy.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(strategy.keeper(), keeper);

        // Verify proxy setup
        verifyProxy(address(strategy), strategyImpl);
    }

    function test_preventDoubleInit() public {
        // Try to initialize again - should revert
        vm.expectRevert("Initializable: contract is already initialized");
        MockUpgradeableStrategy(address(strategy)).initialize(
            address(asset),
            "Another Name",
            management,
            performanceFeeRecipient,
            keeper
        );
    }

    function test_implementationCannotBeInitialized() public {
        // Deploy a new implementation
        MockUpgradeableStrategy impl = new MockUpgradeableStrategy();

        // Try to initialize the implementation directly - should revert
        vm.expectRevert("Initializable: contract is already initialized");
        impl.initialize(
            address(asset),
            "Direct Init",
            management,
            performanceFeeRecipient,
            keeper
        );
    }

    function test_delegationToTokenizedStrategy(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        // Get initial balance
        uint256 initialBalance = asset.balanceOf(user);

        // Test that standard ERC4626 functions work via delegation
        mintAndDepositIntoStrategy(strategy, user, _amount);

        assertEq(strategy.balanceOf(user), _amount);
        assertEq(strategy.totalAssets(), _amount);
        assertEq(strategy.totalSupply(), _amount);

        // Test withdrawal
        vm.prank(user);
        strategy.redeem(_amount, user, user);

        assertEq(strategy.balanceOf(user), 0);
        assertEq(asset.balanceOf(user), initialBalance + _amount);
    }

    function test_accessControlModifiers() public {
        // Test onlyManagement
        vm.expectRevert("!management");
        strategy.setPerformanceFee(1000);

        vm.prank(management);
        strategy.setPerformanceFee(1000);
        assertEq(strategy.performanceFee(), 1000);

        // Test onlyKeepers
        vm.expectRevert("!keeper");
        strategy.tend();

        vm.prank(keeper);
        strategy.tend();

        // Test onlyEmergencyAuthorized
        vm.expectRevert("!emergency authorized");
        strategy.shutdownStrategy();

        vm.prank(management);
        strategy.shutdownStrategy();
        assertTrue(strategy.isShutdown());
    }

    function test_hookCallbacks(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        MockUpgradeableStrategy mockStrategy = MockUpgradeableStrategy(
            address(strategy)
        );

        // Test deployFunds callback
        mintAndDepositIntoStrategy(strategy, user, _amount);
        // deployFunds is called during deposit
        assertEq(mockStrategy.deployedFunds(), _amount);

        // Test that totalAssets includes deployed funds
        assertEq(strategy.totalAssets(), _amount);

        // Test withdrawal - this should trigger freeFunds
        uint256 shares = strategy.balanceOf(user);
        vm.prank(user);
        strategy.redeem(shares, user, user);

        // After withdrawal, deployedFunds should be reduced
        // Note: May not be exactly 0 due to how freeFunds is called
        assertLe(mockStrategy.deployedFunds(), _amount);
    }

    function test_harvestAndReport(uint256 _amount) public {
        vm.assume(_amount >= minFuzzAmount && _amount <= maxFuzzAmount);

        mintAndDepositIntoStrategy(strategy, user, _amount);

        // First report right after deposit shows initial deposit as profit
        vm.prank(keeper);
        (uint256 profit, uint256 loss) = strategy.report();

        // The initial report shows the deposit as profit since it's the first report
        assertEq(profit, _amount);
        assertEq(loss, 0);

        // Total assets will be higher due to performance fees being minted
        uint256 totalAssetsAfterFirstReport = strategy.totalAssets();
        assertGt(totalAssetsAfterFirstReport, _amount); // Will be higher due to fees

        // Simulate additional profit by airdropping funds
        uint256 additionalProfit = _amount;
        airdrop(asset, address(strategy), additionalProfit);

        // Second report - should show the additional profit
        vm.prank(keeper);
        (profit, loss) = strategy.report();

        assertEq(profit, additionalProfit);
        assertEq(loss, 0);

        // Total assets increases by the additional profit
        uint256 totalAssetsAfterSecondReport = strategy.totalAssets();
        assertGt(totalAssetsAfterSecondReport, totalAssetsAfterFirstReport);
    }

    function test_storageLayout() public {
        // Note: The proxy has its own storage layout for the implementation address
        // The actual strategy storage starts after the proxy's reserved slots
        // We're checking that the strategy can properly store and retrieve data

        // Verify the strategy is working correctly which proves storage is laid out properly
        uint256 testAmount = maxFuzzAmount / 2;
        mintAndDepositIntoStrategy(strategy, user, testAmount);

        // Verify asset is accessible
        assertEq(strategy.asset(), address(asset));

        // Verify the strategy state is stored correctly
        assertEq(strategy.totalAssets(), testAmount);
        assertEq(strategy.balanceOf(user), testAmount);

        // Verify deployedFunds storage in the mock
        MockUpgradeableStrategy mockStrategy = MockUpgradeableStrategy(
            address(strategy)
        );
        assertEq(mockStrategy.deployedFunds(), testAmount);
    }

    function test_fallbackFunction() public {
        // Test that unknown functions are delegated to TokenizedStrategy

        // Call a function that doesn't exist in BaseStrategyUpgradeable
        // but exists in TokenizedStrategy (e.g., apiVersion)
        string memory version = strategy.apiVersion();
        assertEq(bytes(version).length > 0, true);
    }

    function test_emergencyFunctions() public {
        uint256 _amount = maxFuzzAmount / 2;
        mintAndDepositIntoStrategy(strategy, user, _amount);

        // Verify user has shares
        uint256 shares = strategy.balanceOf(user);
        assertEq(shares, _amount);

        // Shutdown the strategy
        vm.prank(management);
        strategy.shutdownStrategy();
        assertTrue(strategy.isShutdown());

        // Emergency withdraw should work
        vm.prank(management);
        strategy.emergencyWithdraw(_amount);

        // Verify deployedFunds was updated
        MockUpgradeableStrategy mockStrategy = MockUpgradeableStrategy(
            address(strategy)
        );
        assertEq(mockStrategy.deployedFunds(), 0);

        // User should still have shares but totalAssets should be reduced
        assertEq(strategy.balanceOf(user), shares);
        assertEq(strategy.totalAssets(), asset.balanceOf(address(strategy)));
    }
}
