// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {UpgradeableSetup, IStrategy, SafeERC20, ERC20} from "../utils/UpgradeableSetup.sol";
import {MockUpgradeableStrategy, MockUpgradeableStrategyV2} from "../mocks/MockUpgradeableStrategy.sol";
import {MockHealthCheckUpgradeable} from "../mocks/MockHealthCheckUpgradeable.sol";
import {MockHooksUpgradeable} from "../mocks/MockHooksUpgradeable.sol";

contract StorageLayoutTest is UpgradeableSetup {
    using SafeERC20 for ERC20;

    function test_baseStrategyStorageLayout() public {
        // Deploy strategy
        address impl = address(new MockUpgradeableStrategy());
        address proxy = deployUpgradeableStrategy(
            impl,
            address(asset),
            "Storage Test"
        );
        
        // Verify slot 0 contains packed data from TokenizedStrategy
        // The asset is part of this packed data but not easily extractable
        // We verify it through the strategy's asset() function instead
        bytes32 slot0 = readStorageSlot(proxy, 0);
        assertFalse(slot0 == bytes32(0), "Slot 0 should not be empty");
        assertEq(IStrategy(proxy).asset(), address(asset), "Strategy should return correct asset");
        
        // Verify slot 1: TokenizedStrategy in BaseStrategyUpgradeable 
        // This is set to address(this) which is the proxy
        bytes32 slot1 = readStorageSlot(proxy, 1);
        address tokenizedFromStorage = address(uint160(uint256(slot1)));
        assertEq(tokenizedFromStorage, proxy, "Slot 1 should contain TokenizedStrategy (proxy address)");
        
        // Verify slots 2-9: gap (should be empty initially)
        for (uint256 i = 2; i <= 9; i++) {
            bytes32 gapSlot = readStorageSlot(proxy, i);
            assertEq(gapSlot, bytes32(0), string.concat("Gap slot ", vm.toString(i), " should be empty"));
        }
        
        // Slot 10 is where strategy implementations can start adding storage
        // For MockUpgradeableStrategy, slot 10 contains deployedFunds
        mintAndDepositIntoStrategy(IStrategy(proxy), user, maxFuzzAmount);
        
        bytes32 slot10 = readStorageSlot(proxy, 10);
        uint256 deployedFunds = uint256(slot10);
        assertEq(deployedFunds, maxFuzzAmount, "Slot 10 should contain deployedFunds");
    }

    function test_healthCheckStorageLayout() public {
        // Deploy health check strategy
        address impl = address(new MockHealthCheckUpgradeable());
        address proxy = deployUpgradeableStrategy(
            impl,
            address(asset),
            "Health Check Storage"
        );
        
        MockHealthCheckUpgradeable healthCheck = MockHealthCheckUpgradeable(proxy);
        
        // Verify base storage (slots 0-9)
        bytes32 slot0 = readStorageSlot(proxy, 0);
        assertFalse(slot0 == bytes32(0), "Slot 0 should not be empty");
        assertEq(IStrategy(address(healthCheck)).asset(), address(asset), "Asset accessible via function");
        
        // Slot 1 contains TokenizedStrategy address (the proxy itself)
        bytes32 slot1 = readStorageSlot(proxy, 1);
        assertEq(address(uint160(uint256(slot1))), proxy, "TokenizedStrategy in slot 1");
        
        // Verify slot 10: packed storage (doHealthCheck, _profitLimitRatio, _lossLimitRatio)
        bytes32 slot10 = readStorageSlot(proxy, 10);
        
        // Extract packed values
        uint256 packedValue = uint256(slot10);
        bool doHealthCheck = uint8(packedValue) != 0;
        uint16 profitRatio = uint16(packedValue >> 8);
        uint16 lossRatio = uint16(packedValue >> 24);
        
        assertEq(doHealthCheck, true, "doHealthCheck should be true");
        assertEq(profitRatio, 10_000, "profitLimitRatio should be 10000");
        assertEq(lossRatio, 0, "lossLimitRatio should be 0");
        
        // Modify values and verify packing
        vm.startPrank(management);
        healthCheck.setDoHealthCheck(false);
        healthCheck.setProfitLimitRatio(5_000);
        healthCheck.setLossLimitRatio(2_500);
        vm.stopPrank();
        
        slot10 = readStorageSlot(proxy, 10);
        packedValue = uint256(slot10);
        doHealthCheck = uint8(packedValue) != 0;
        profitRatio = uint16(packedValue >> 8);
        lossRatio = uint16(packedValue >> 24);
        
        assertEq(doHealthCheck, false, "doHealthCheck should be false");
        assertEq(profitRatio, 5_000, "profitLimitRatio should be 5000");
        assertEq(lossRatio, 2_500, "lossLimitRatio should be 2500");
        
        // Verify gap slots 11-19
        for (uint256 i = 11; i <= 19; i++) {
            bytes32 gapSlot = readStorageSlot(proxy, i);
            assertEq(gapSlot, bytes32(0), string.concat("Health check gap slot ", vm.toString(i), " should be empty"));
        }
    }

    function test_hooksNoAdditionalStorage() public {
        // Deploy hooks strategy
        address impl = address(new MockHooksUpgradeable());
        address proxy = deployUpgradeableStrategy(
            impl,
            address(asset),
            "Hooks Storage"
        );
        
        // Hooks should not add any storage beyond health check
        // Verify slots 0-19 match health check pattern
        
        // Base strategy slots (0-9)
        bytes32 slot0 = readStorageSlot(proxy, 0);
        assertFalse(slot0 == bytes32(0), "Slot 0 should not be empty");
        assertEq(IStrategy(proxy).asset(), address(asset), "Asset accessible via function");
        
        // Health check slot (10)
        bytes32 slot10 = readStorageSlot(proxy, 10);
        uint256 packedValue = uint256(slot10);
        bool doHealthCheck = uint8(packedValue) != 0;
        assertEq(doHealthCheck, true, "Health check values should be initialized");
        
        // Verify no additional storage used (slots 20+)
        for (uint256 i = 20; i <= 30; i++) {
            bytes32 slot = readStorageSlot(proxy, i);
            assertEq(slot, bytes32(0), string.concat("Slot ", vm.toString(i), " should be empty (hooks adds no storage)"));
        }
    }

    function test_crossVersionCompatibility() public {
        // Deploy V1
        address implV1 = address(new MockUpgradeableStrategy());
        address proxy = deployUpgradeableStrategy(
            implV1,
            address(asset),
            "Version Test"
        );
        
        MockUpgradeableStrategy v1 = MockUpgradeableStrategy(proxy);
        
        // Add data in V1
        mintAndDepositIntoStrategy(IStrategy(proxy), user, maxFuzzAmount);
        assertEq(v1.deployedFunds(), maxFuzzAmount);
        
        // Store slot 10 value (deployedFunds in V1)
        bytes32 slot10Before = readStorageSlot(proxy, 10);
        
        // Upgrade to V2
        address implV2 = address(new MockUpgradeableStrategyV2());
        upgradeProxy(proxy, implV2);
        
        MockUpgradeableStrategyV2 v2 = MockUpgradeableStrategyV2(proxy);
        
        // Verify slot 10 unchanged (deployedFunds preserved)
        bytes32 slot10After = readStorageSlot(proxy, 10);
        assertEq(slot10After, slot10Before, "Slot 10 should be preserved");
        assertEq(v2.deployedFunds(), maxFuzzAmount, "deployedFunds value preserved");
        
        // Add new V2 data (uses slot 11 for newVariable)
        vm.prank(management);
        v2.setNewVariable(12345);
        
        bytes32 slot11 = readStorageSlot(proxy, 11);
        assertEq(uint256(slot11), 12345, "New variable stored in slot 11");
        
        // Mapping data goes to computed slots
        vm.prank(management);
        v2.setUserBalance(user, 99999);
        
        // Verify original functionality still works
        assertEq(v2.deployedFunds(), maxFuzzAmount);
        assertEq(v2.newVariable(), 12345);
        assertEq(v2.userBalances(user), 99999);
    }

    function test_storageCollisionPrevention() public {
        // This test verifies that the storage layout prevents collisions
        
        // Deploy strategy with known storage values
        address impl = address(new MockUpgradeableStrategy());
        address proxy = deployUpgradeableStrategy(
            impl,
            address(asset),
            "Collision Test"
        );
        
        // Set up some state
        mintAndDepositIntoStrategy(IStrategy(proxy), user, maxFuzzAmount);
        
        // Read all relevant slots
        bytes32[] memory originalSlots = new bytes32[](20);
        for (uint256 i = 0; i < 20; i++) {
            originalSlots[i] = readStorageSlot(proxy, i);
        }
        
        // Upgrade to health check
        address healthImpl = address(new MockHealthCheckUpgradeable());
        upgradeProxy(proxy, healthImpl);
        
        // Verify base slots unchanged
        for (uint256 i = 0; i < 10; i++) {
            bytes32 currentSlot = readStorageSlot(proxy, i);
            assertEq(currentSlot, originalSlots[i], string.concat("Slot ", vm.toString(i), " should be unchanged"));
        }
        
        // Upgrade to hooks
        address hooksImpl = address(new MockHooksUpgradeable());
        upgradeProxy(proxy, hooksImpl);
        
        // Verify base slots still unchanged
        for (uint256 i = 0; i < 10; i++) {
            bytes32 currentSlot = readStorageSlot(proxy, i);
            assertEq(currentSlot, originalSlots[i], string.concat("Slot ", vm.toString(i), " should still be unchanged"));
        }
    }

    function test_gapUsageInUpgrade() public {
        // Deploy V1
        address implV1 = address(new MockUpgradeableStrategy());
        address proxy = deployUpgradeableStrategy(
            implV1,
            address(asset),
            "Gap Usage Test"
        );
        
        // V1 uses slot 10 for deployedFunds
        mintAndDepositIntoStrategy(IStrategy(proxy), user, maxFuzzAmount);
        
        // Verify gap is available
        for (uint256 i = 2; i <= 9; i++) {
            bytes32 slot = readStorageSlot(proxy, i);
            assertEq(slot, bytes32(0), "Gap should be empty");
        }
        
        // Upgrade to V2 which adds storage
        address implV2 = address(new MockUpgradeableStrategyV2());
        upgradeProxy(proxy, implV2);
        
        MockUpgradeableStrategyV2 v2 = MockUpgradeableStrategyV2(proxy);
        
        // V2 adds newVariable at slot 11
        vm.prank(management);
        v2.setNewVariable(0xDEADBEEF);
        
        bytes32 slot11 = readStorageSlot(proxy, 11);
        assertEq(uint256(slot11), 0xDEADBEEF, "New variable uses slot 11");
        
        // Original data still intact
        assertEq(v2.deployedFunds(), maxFuzzAmount, "Original data preserved");
        
        // Gap slots 2-9 still available for future upgrades
        for (uint256 i = 2; i <= 9; i++) {
            bytes32 slot = readStorageSlot(proxy, i);
            assertEq(slot, bytes32(0), "Gap still available for future use");
        }
    }
}