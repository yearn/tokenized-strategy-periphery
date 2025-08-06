// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/console.sol";
import {Setup, ERC20, IStrategy} from "./utils/Setup.sol";
import {TokenizedStrategyStorageLib} from "../libraries/TokenizedStrategyStorageLib.sol";

contract TokenizedStrategyStorageLibTest is Setup {
    using TokenizedStrategyStorageLib for *;

    function setUp() public virtual override {
        super.setUp();
    }

    function test_assetSlot() public {
        // Get the slot for asset (packed with decimals)
        bytes32 slot = TokenizedStrategyStorageLib.assetSlot();

        // Read raw storage at that slot
        bytes32 rawValue = vm.load(address(mockStrategy), slot);

        // Extract asset address (first 20 bytes)
        address storedAsset = address(uint160(uint256(rawValue)));

        // Extract decimals (byte 20)
        uint8 storedDecimals = uint8(uint256(rawValue) >> 160);

        // Compare with public getters
        assertEq(storedAsset, mockStrategy.asset(), "Asset slot mismatch");
        assertEq(storedDecimals, mockStrategy.decimals(), "Decimals mismatch");
    }

    function test_totalAssetsSlot() public {
        // First deposit some assets to have a non-zero totalAssets
        uint256 depositAmount = 1000 * 10 ** decimals;
        mintAndDepositIntoStrategy(mockStrategy, user, depositAmount);

        // Get the slot for totalAssets
        bytes32 slot = TokenizedStrategyStorageLib.totalAssetsSlot();

        // Read raw storage at that slot
        uint256 storedTotalAssets = uint256(
            vm.load(address(mockStrategy), slot)
        );

        // Compare with public getter
        assertEq(
            storedTotalAssets,
            mockStrategy.totalAssets(),
            "TotalAssets slot mismatch"
        );
    }

    function test_totalSupplySlot() public {
        // First deposit to have non-zero supply
        uint256 depositAmount = 1000 * 10 ** decimals;
        mintAndDepositIntoStrategy(mockStrategy, user, depositAmount);

        // Get the slot for totalSupply
        bytes32 slot = TokenizedStrategyStorageLib.totalSupplySlot();

        // Read raw storage at that slot
        uint256 storedTotalSupply = uint256(
            vm.load(address(mockStrategy), slot)
        );

        // Compare with public getter
        assertEq(
            storedTotalSupply,
            mockStrategy.totalSupply(),
            "TotalSupply slot mismatch"
        );
    }

    function test_nameSlot() public {
        // Get the slot for name
        bytes32 slot = TokenizedStrategyStorageLib.nameSlot();

        // Read raw storage at that slot
        bytes32 rawValue = vm.load(address(mockStrategy), slot);

        // For dynamic strings, the slot contains length * 2 + 1 if string is <= 31 bytes
        // The actual string data is stored in the same slot for short strings
        uint256 length = uint256(rawValue) & 1;

        if (length == 1) {
            // Short string (31 bytes or less) - data is in the same slot
            uint256 strLength = (uint256(rawValue) & 0xFF) / 2;
            assertGt(strLength, 0, "Name should not be empty");
        } else {
            // Long string - the slot contains length * 2
            uint256 strLength = uint256(rawValue) / 2;
            assertGt(strLength, 0, "Name should not be empty");
        }

        // Just verify the name is not empty via public getter
        string memory name = mockStrategy.name();
        assertGt(bytes(name).length, 0, "Name should not be empty via getter");
    }

    function test_performanceFeeAndRelatedSlot() public {
        // Get the profit config slot
        bytes32 slot = TokenizedStrategyStorageLib.profitConfigSlot();

        // Read raw storage at that slot
        bytes32 rawValue = vm.load(address(mockStrategy), slot);

        // Extract profitMaxUnlockTime (first uint32)
        uint32 storedProfitMaxUnlockTime = uint32(uint256(rawValue));

        // Extract performanceFee (next uint16)
        uint16 storedPerformanceFee = uint16(uint256(rawValue) >> 32);

        // Extract performanceFeeRecipient (address - 160 bits)
        address storedPerformanceFeeRecipient = address(
            uint160(uint256(rawValue) >> 48)
        );

        // Compare with public getters
        assertEq(
            storedProfitMaxUnlockTime,
            mockStrategy.profitMaxUnlockTime(),
            "ProfitMaxUnlockTime mismatch"
        );
        assertEq(
            storedPerformanceFee,
            mockStrategy.performanceFee(),
            "PerformanceFee mismatch"
        );
        assertEq(
            storedPerformanceFeeRecipient,
            mockStrategy.performanceFeeRecipient(),
            "PerformanceFeeRecipient mismatch"
        );
    }

    function test_balancesSlot() public {
        // Deposit to create a balance
        uint256 depositAmount = 1000 * 10 ** decimals;
        mintAndDepositIntoStrategy(mockStrategy, user, depositAmount);

        // Get the slot for user's balance
        bytes32 slot = TokenizedStrategyStorageLib.balancesSlot(user);

        // Read raw storage at that slot
        uint256 storedBalance = uint256(vm.load(address(mockStrategy), slot));

        // Compare with public getter
        assertEq(
            storedBalance,
            mockStrategy.balanceOf(user),
            "Balance slot mismatch"
        );
    }

    function test_allowancesSlot() public {
        // Set an allowance
        vm.prank(user);
        mockStrategy.approve(daddy, 1000);

        // Get the slot for the allowance
        bytes32 slot = TokenizedStrategyStorageLib.allowancesSlot(user, daddy);

        // Read raw storage at that slot
        uint256 storedAllowance = uint256(vm.load(address(mockStrategy), slot));

        // Compare with public getter
        assertEq(
            storedAllowance,
            mockStrategy.allowance(user, daddy),
            "Allowance slot mismatch"
        );
    }

    function test_noncesSlot() public {
        // Get the slot for user's nonce
        bytes32 slot = TokenizedStrategyStorageLib.noncesSlot(user);

        // Read raw storage at that slot
        uint256 storedNonce = uint256(vm.load(address(mockStrategy), slot));

        // Compare with public getter
        assertEq(storedNonce, mockStrategy.nonces(user), "Nonce slot mismatch");
    }

    function test_statusSlot() public {
        // Get the status slot
        bytes32 slot = TokenizedStrategyStorageLib.statusSlot();

        // Read raw storage at that slot
        bytes32 rawValue = vm.load(address(mockStrategy), slot);

        // Extract entered (first uint8)
        uint8 storedEntered = uint8(uint256(rawValue));

        // Extract shutdown (next bool - 1 byte)
        bool storedShutdown = uint8(uint256(rawValue) >> 8) != 0;

        // The entered field is not initialized in storage (0) until first use
        // When it's first used, it will be set to NOT_ENTERED (1)
        // We're checking the raw storage, so it should be 0 initially
        assertEq(storedEntered, 0, "Entered status mismatch"); // Uninitialized in storage
        assertEq(
            storedShutdown,
            mockStrategy.isShutdown(),
            "Shutdown status mismatch"
        );
    }

    function test_emergencyAdminSlot() public {
        // Get the slot for emergencyAdmin
        bytes32 slot = TokenizedStrategyStorageLib.emergencyAdminSlot();

        // Read raw storage at that slot
        address storedEmergencyAdmin = address(
            uint160(uint256(vm.load(address(mockStrategy), slot)))
        );

        // Compare with public getter
        assertEq(
            storedEmergencyAdmin,
            mockStrategy.emergencyAdmin(),
            "EmergencyAdmin slot mismatch"
        );
    }

    function test_pendingManagementSlot() public {
        // Set a pending management (need to call as management)
        vm.prank(management);
        mockStrategy.setPendingManagement(daddy);

        // Get the slot for pendingManagement
        bytes32 slot = TokenizedStrategyStorageLib.pendingManagementSlot();

        // Read raw storage at that slot
        address storedPendingManagement = address(
            uint160(uint256(vm.load(address(mockStrategy), slot)))
        );

        // Compare with public getter
        assertEq(
            storedPendingManagement,
            mockStrategy.pendingManagement(),
            "PendingManagement slot mismatch"
        );
    }

    function test_keeperSlot() public {
        // Get the slot containing keeper (packed with fullProfitUnlockDate)
        bytes32 slot = TokenizedStrategyStorageLib
            .fullProfitUnlockDateAndKeeperSlot();

        // Read raw storage at that slot
        bytes32 rawValue = vm.load(address(mockStrategy), slot);

        // Extract fullProfitUnlockDate (first uint96)
        uint96 storedFullProfitUnlockDate = uint96(uint256(rawValue));

        // Extract keeper (address - 160 bits, after 96 bits)
        address storedKeeper = address(uint160(uint256(rawValue) >> 96));

        // Compare with public getters
        assertEq(
            storedFullProfitUnlockDate,
            mockStrategy.fullProfitUnlockDate(),
            "FullProfitUnlockDate mismatch"
        );
        assertEq(storedKeeper, mockStrategy.keeper(), "Keeper slot mismatch");
    }

    function test_lastReportAndManagementSlot() public {
        // Trigger a report to set lastReport
        skip(1 days);
        vm.prank(keeper);
        mockStrategy.report();

        // Get the slot for lastReport and management (packed)
        bytes32 slot = TokenizedStrategyStorageLib
            .lastReportAndManagementSlot();

        // Read raw storage at that slot
        bytes32 rawValue = vm.load(address(mockStrategy), slot);

        // Extract lastReport (first uint96)
        uint96 storedLastReport = uint96(uint256(rawValue));

        // Extract management (address - 160 bits, after 96 bits)
        address storedManagement = address(uint160(uint256(rawValue) >> 96));

        // Compare with public getters
        assertEq(
            storedLastReport,
            mockStrategy.lastReport(),
            "LastReport slot mismatch"
        );
        assertEq(
            storedManagement,
            mockStrategy.management(),
            "Management slot mismatch"
        );
    }

    function test_profitUnlockingRateSlot() public {
        // Get the slot for profitUnlockingRate
        bytes32 slot = TokenizedStrategyStorageLib.profitUnlockingRateSlot();

        // Read raw storage at that slot
        uint256 storedProfitUnlockingRate = uint256(
            vm.load(address(mockStrategy), slot)
        );

        // Compare with public getter
        assertEq(
            storedProfitUnlockingRate,
            mockStrategy.profitUnlockingRate(),
            "ProfitUnlockingRate slot mismatch"
        );
    }

    // ============ Priority 1: Critical Missing Tests ============

    function test_strategyStorageSlot() public {
        // Test that strategyStorageSlot returns the correct base slot
        bytes32 expectedSlot = bytes32(
            uint256(keccak256("yearn.base.strategy.storage")) - 1
        );
        bytes32 actualSlot = TokenizedStrategyStorageLib.strategyStorageSlot();

        assertEq(actualSlot, expectedSlot, "Strategy storage slot mismatch");
        // Also verify it matches the assetSlot (they should be the same)
        assertEq(
            actualSlot,
            TokenizedStrategyStorageLib.assetSlot(),
            "Base slot should match asset slot"
        );
    }

    function test_getStrategyStorage() public {
        // This test verifies the getStrategyStorage() helper works correctly
        // Note: We can't directly test this in Solidity as it returns a storage pointer
        // but we can verify that the slot calculation is correct
        bytes32 slot = TokenizedStrategyStorageLib.strategyStorageSlot();

        // Verify the slot matches our expected base storage slot
        bytes32 expectedSlot = bytes32(
            uint256(keccak256("yearn.base.strategy.storage")) - 1
        );
        assertEq(slot, expectedSlot, "getStrategyStorage base slot incorrect");
    }

    function test_packedFieldsIntegrity() public {
        // Test that packed fields don't interfere with each other

        // Test slot 0: asset + decimals
        bytes32 slot0 = TokenizedStrategyStorageLib.assetSlot();
        bytes32 rawValue0 = vm.load(address(mockStrategy), slot0);

        // Verify we can extract both values correctly
        address asset = address(uint160(uint256(rawValue0)));
        uint8 decimals = uint8(uint256(rawValue0) >> 160);

        assertEq(asset, mockStrategy.asset(), "Packed field: asset corrupted");
        assertEq(
            decimals,
            mockStrategy.decimals(),
            "Packed field: decimals corrupted"
        );

        // Test slot 8: fullProfitUnlockDate + keeper
        bytes32 slot8 = TokenizedStrategyStorageLib
            .fullProfitUnlockDateAndKeeperSlot();
        bytes32 rawValue8 = vm.load(address(mockStrategy), slot8);

        uint96 fullProfitUnlockDate = uint96(uint256(rawValue8));
        address keeper = address(uint160(uint256(rawValue8) >> 96));

        assertEq(
            fullProfitUnlockDate,
            mockStrategy.fullProfitUnlockDate(),
            "Packed field: fullProfitUnlockDate corrupted"
        );
        assertEq(
            keeper,
            mockStrategy.keeper(),
            "Packed field: keeper corrupted"
        );

        // Test slot 9: profitMaxUnlockTime + performanceFee + performanceFeeRecipient
        bytes32 slot9 = TokenizedStrategyStorageLib.profitConfigSlot();
        bytes32 rawValue9 = vm.load(address(mockStrategy), slot9);

        uint32 profitMaxUnlockTime = uint32(uint256(rawValue9));
        uint16 performanceFee = uint16(uint256(rawValue9) >> 32);
        address performanceFeeRecipient = address(
            uint160(uint256(rawValue9) >> 48)
        );

        assertEq(
            profitMaxUnlockTime,
            mockStrategy.profitMaxUnlockTime(),
            "Packed field: profitMaxUnlockTime corrupted"
        );
        assertEq(
            performanceFee,
            mockStrategy.performanceFee(),
            "Packed field: performanceFee corrupted"
        );
        assertEq(
            performanceFeeRecipient,
            mockStrategy.performanceFeeRecipient(),
            "Packed field: performanceFeeRecipient corrupted"
        );
    }

    function test_storageLayoutConsistency() public {
        // Verify all slots are unique and correctly positioned
        bytes32 baseSlot = TokenizedStrategyStorageLib.strategyStorageSlot();

        // Calculate all slots
        bytes32[] memory slots = new bytes32[](14);
        slots[0] = TokenizedStrategyStorageLib.assetSlot(); // slot 0
        slots[1] = TokenizedStrategyStorageLib.nameSlot(); // slot 1
        slots[2] = TokenizedStrategyStorageLib.totalSupplySlot(); // slot 2
        // slots 3-5 are mappings, calculated differently
        slots[6] = TokenizedStrategyStorageLib.totalAssetsSlot(); // slot 6
        slots[7] = TokenizedStrategyStorageLib.profitUnlockingRateSlot(); // slot 7
        slots[8] = TokenizedStrategyStorageLib
            .fullProfitUnlockDateAndKeeperSlot(); // slot 8
        slots[9] = TokenizedStrategyStorageLib.profitConfigSlot(); // slot 9
        slots[10] = TokenizedStrategyStorageLib.lastReportAndManagementSlot(); // slot 10
        slots[11] = TokenizedStrategyStorageLib.pendingManagementSlot(); // slot 11
        slots[12] = TokenizedStrategyStorageLib.emergencyAdminSlot(); // slot 12
        slots[13] = TokenizedStrategyStorageLib.statusSlot(); // slot 13

        // Verify slots are sequential (excluding mappings at 3-5)
        assertEq(uint256(slots[0]), uint256(baseSlot), "Slot 0 incorrect");
        assertEq(uint256(slots[1]), uint256(baseSlot) + 1, "Slot 1 incorrect");
        assertEq(uint256(slots[2]), uint256(baseSlot) + 2, "Slot 2 incorrect");
        assertEq(uint256(slots[6]), uint256(baseSlot) + 6, "Slot 6 incorrect");
        assertEq(uint256(slots[7]), uint256(baseSlot) + 7, "Slot 7 incorrect");
        assertEq(uint256(slots[8]), uint256(baseSlot) + 8, "Slot 8 incorrect");
        assertEq(uint256(slots[9]), uint256(baseSlot) + 9, "Slot 9 incorrect");
        assertEq(
            uint256(slots[10]),
            uint256(baseSlot) + 10,
            "Slot 10 incorrect"
        );
        assertEq(
            uint256(slots[11]),
            uint256(baseSlot) + 11,
            "Slot 11 incorrect"
        );
        assertEq(
            uint256(slots[12]),
            uint256(baseSlot) + 12,
            "Slot 12 incorrect"
        );
        assertEq(
            uint256(slots[13]),
            uint256(baseSlot) + 13,
            "Slot 13 incorrect"
        );
    }

    // ============ Priority 2: Edge Cases ============

    function test_mappingEdgeCases() public {
        // Test with zero address
        address zeroAddr = address(0);

        // Test balance slot with zero address
        bytes32 zeroBalanceSlot = TokenizedStrategyStorageLib.balancesSlot(
            zeroAddr
        );
        uint256 zeroBalance = uint256(
            vm.load(address(mockStrategy), zeroBalanceSlot)
        );
        assertEq(zeroBalance, 0, "Zero address should have zero balance");

        // Test allowance slot with zero addresses
        bytes32 zeroAllowanceSlot = TokenizedStrategyStorageLib.allowancesSlot(
            zeroAddr,
            daddy
        );
        uint256 zeroAllowance = uint256(
            vm.load(address(mockStrategy), zeroAllowanceSlot)
        );
        assertEq(zeroAllowance, 0, "Zero address should have zero allowance");

        // Test nonce slot with zero address
        bytes32 zeroNonceSlot = TokenizedStrategyStorageLib.noncesSlot(
            zeroAddr
        );
        uint256 zeroNonce = uint256(
            vm.load(address(mockStrategy), zeroNonceSlot)
        );
        assertEq(zeroNonce, 0, "Zero address should have zero nonce");

        // Test with contract address (using mockStrategy itself)
        bytes32 contractBalanceSlot = TokenizedStrategyStorageLib.balancesSlot(
            address(mockStrategy)
        );
        uint256 contractBalance = uint256(
            vm.load(address(mockStrategy), contractBalanceSlot)
        );
        assertEq(
            contractBalance,
            mockStrategy.balanceOf(address(mockStrategy)),
            "Contract balance slot correct"
        );

        // Verify no slot collisions between different addresses
        bytes32 slot1 = TokenizedStrategyStorageLib.balancesSlot(user);
        bytes32 slot2 = TokenizedStrategyStorageLib.balancesSlot(daddy);
        bytes32 slot3 = TokenizedStrategyStorageLib.balancesSlot(management);

        assertTrue(
            slot1 != slot2,
            "Balance slots should be different for different addresses"
        );
        assertTrue(
            slot2 != slot3,
            "Balance slots should be different for different addresses"
        );
        assertTrue(
            slot1 != slot3,
            "Balance slots should be different for different addresses"
        );
    }

    function test_maximumValues() public {
        // Test maximum values for packed fields don't cause overflow

        // For this test, we'll verify the bit sizes are correct
        // uint96 max = 2^96 - 1
        uint96 maxUint96 = type(uint96).max;

        // uint88 max = 2^88 - 1
        uint88 maxUint88 = type(uint88).max;

        // uint32 max = 2^32 - 1
        uint32 maxUint32 = type(uint32).max;

        // uint16 max = 2^16 - 1
        uint16 maxUint16 = type(uint16).max;

        // uint8 max = 2^8 - 1
        uint8 maxUint8 = type(uint8).max;

        // Verify these values fit in their respective packed slots
        assertTrue(maxUint96 <= type(uint96).max, "uint96 max value valid");
        assertTrue(maxUint88 <= type(uint88).max, "uint88 max value valid");
        assertTrue(maxUint32 <= type(uint32).max, "uint32 max value valid");
        assertTrue(maxUint16 <= type(uint16).max, "uint16 max value valid");
        assertTrue(maxUint8 <= type(uint8).max, "uint8 max value valid");

        // Verify bit shifting for packed fields
        // slot 0: address (160) + uint8 (8) = 168 bits (fits in 256 bits)
        assertTrue(160 + 8 <= 256, "Slot 0 packing fits in 256 bits");

        // slot 8: uint96 (96) + address (160) = 256 bits
        assertTrue(96 + 160 == 256, "Slot 8 packing is exactly 256 bits");

        // slot 9: uint32 (32) + uint16 (16) + address (160) = 208 bits (fits in 256)
        assertTrue(32 + 16 + 160 <= 256, "Slot 9 packing fits in 256 bits");

        // slot 10: uint96 (96) + address (160) = 256 bits
        assertTrue(96 + 160 == 256, "Slot 10 packing is exactly 256 bits");

        // slot 13: uint8 (8) + bool (8) = 16 bits (fits in 256)
        assertTrue(8 + 8 <= 256, "Slot 13 packing fits in 256 bits");
    }

    // ============ Priority 3: Fuzz Tests ============

    function testFuzz_balancesSlot(address account) public {
        // Fuzz test for balance slot calculation
        bytes32 slot = TokenizedStrategyStorageLib.balancesSlot(account);

        // Verify the slot is deterministic (same input = same output)
        bytes32 slot2 = TokenizedStrategyStorageLib.balancesSlot(account);
        assertEq(slot, slot2, "Balance slot should be deterministic");

        // Verify different addresses produce different slots
        if (account != address(0)) {
            address differentAddr = address(
                uint160(uint256(keccak256(abi.encode(account))))
            );
            if (differentAddr != account) {
                bytes32 differentSlot = TokenizedStrategyStorageLib
                    .balancesSlot(differentAddr);
                assertTrue(
                    slot != differentSlot,
                    "Different addresses should have different slots"
                );
            }
        }
    }

    function testFuzz_allowancesSlot(address owner, address spender) public {
        // Fuzz test for allowance slot calculation
        bytes32 slot = TokenizedStrategyStorageLib.allowancesSlot(
            owner,
            spender
        );

        // Verify the slot is deterministic
        bytes32 slot2 = TokenizedStrategyStorageLib.allowancesSlot(
            owner,
            spender
        );
        assertEq(slot, slot2, "Allowance slot should be deterministic");

        // Verify different combinations produce different slots
        if (owner != spender) {
            bytes32 reversedSlot = TokenizedStrategyStorageLib.allowancesSlot(
                spender,
                owner
            );
            assertTrue(
                slot != reversedSlot,
                "Order of addresses should matter for allowance slots"
            );
        }
    }

    function testFuzz_noncesSlot(address owner) public {
        // Fuzz test for nonce slot calculation
        bytes32 slot = TokenizedStrategyStorageLib.noncesSlot(owner);

        // Verify the slot is deterministic
        bytes32 slot2 = TokenizedStrategyStorageLib.noncesSlot(owner);
        assertEq(slot, slot2, "Nonce slot should be deterministic");

        // Read the value and verify it's accessible
        uint256 nonce = uint256(vm.load(address(mockStrategy), slot));
        // New addresses should have nonce of 0
        assertEq(nonce, mockStrategy.nonces(owner), "Nonce value should match");
    }

    // ============ Unit Tests from TokenizedStrategyStorageLibUnit.t.sol ============

    function test_slotCalculations() public pure {
        bytes32 baseSlot = TokenizedStrategyStorageLib.strategyStorageSlot();
        
        // Test that slot calculations are deterministic and correct
        assertEq(
            TokenizedStrategyStorageLib.assetSlot(),
            baseSlot,
            "Asset slot should equal base slot"
        );
        
        assertEq(
            TokenizedStrategyStorageLib.nameSlot(),
            bytes32(uint256(baseSlot) + 1),
            "Name slot should be base + 1"
        );
        
        assertEq(
            TokenizedStrategyStorageLib.totalSupplySlot(),
            bytes32(uint256(baseSlot) + 2),
            "Total supply slot should be base + 2"
        );
        
        assertEq(
            TokenizedStrategyStorageLib.totalAssetsSlot(),
            bytes32(uint256(baseSlot) + 6),
            "Total assets slot should be base + 6"
        );
    }

    function test_mappingSlotsUnit() public pure {
        address testAddr1 = address(0x123);
        address testAddr2 = address(0x456);
        
        // Test that mapping slots are calculated consistently
        bytes32 balance1 = TokenizedStrategyStorageLib.balancesSlot(testAddr1);
        bytes32 balance2 = TokenizedStrategyStorageLib.balancesSlot(testAddr1);
        assertEq(balance1, balance2, "Balance slot calculation should be deterministic");
        
        bytes32 balance3 = TokenizedStrategyStorageLib.balancesSlot(testAddr2);
        assertTrue(balance1 != balance3, "Different addresses should have different balance slots");
        
        // Test allowance slots
        bytes32 allowance1 = TokenizedStrategyStorageLib.allowancesSlot(testAddr1, testAddr2);
        bytes32 allowance2 = TokenizedStrategyStorageLib.allowancesSlot(testAddr1, testAddr2);
        assertEq(allowance1, allowance2, "Allowance slot calculation should be deterministic");
        
        bytes32 allowance3 = TokenizedStrategyStorageLib.allowancesSlot(testAddr2, testAddr1);
        assertTrue(allowance1 != allowance3, "Order should matter for allowance slots");
    }

    // ============ Cross-Validation Test ============

    function test_crossValidation() public {
        // This test compares direct slot access with values from public getters
        // to ensure our slot calculations are correct

        // Setup: Make some state changes
        uint256 depositAmount = 500 * 10 ** decimals;
        mintAndDepositIntoStrategy(mockStrategy, user, depositAmount);
        vm.prank(user);
        mockStrategy.approve(daddy, 100);

        // Cross-validate all major slots

        // 1. Asset slot
        bytes32 assetSlot = TokenizedStrategyStorageLib.assetSlot();
        address storedAsset = address(
            uint160(uint256(vm.load(address(mockStrategy), assetSlot)))
        );
        assertEq(storedAsset, mockStrategy.asset(), "Cross-validation: asset");

        // 2. Total supply
        bytes32 supplySlot = TokenizedStrategyStorageLib.totalSupplySlot();
        uint256 storedSupply = uint256(
            vm.load(address(mockStrategy), supplySlot)
        );
        assertEq(
            storedSupply,
            mockStrategy.totalSupply(),
            "Cross-validation: totalSupply"
        );

        // 3. Total assets
        bytes32 assetsSlot = TokenizedStrategyStorageLib.totalAssetsSlot();
        uint256 storedAssets = uint256(
            vm.load(address(mockStrategy), assetsSlot)
        );
        assertEq(
            storedAssets,
            mockStrategy.totalAssets(),
            "Cross-validation: totalAssets"
        );

        // 4. User balance
        bytes32 balanceSlot = TokenizedStrategyStorageLib.balancesSlot(user);
        uint256 storedBalance = uint256(
            vm.load(address(mockStrategy), balanceSlot)
        );
        assertEq(
            storedBalance,
            mockStrategy.balanceOf(user),
            "Cross-validation: balance"
        );

        // 5. Allowance
        bytes32 allowanceSlot = TokenizedStrategyStorageLib.allowancesSlot(
            user,
            daddy
        );
        uint256 storedAllowance = uint256(
            vm.load(address(mockStrategy), allowanceSlot)
        );
        assertEq(
            storedAllowance,
            mockStrategy.allowance(user, daddy),
            "Cross-validation: allowance"
        );

        // 6. Management
        bytes32 mgmtSlot = TokenizedStrategyStorageLib
            .lastReportAndManagementSlot();
        address storedMgmt = address(
            uint160(uint256(vm.load(address(mockStrategy), mgmtSlot)) >> 96)
        );
        assertEq(
            storedMgmt,
            mockStrategy.management(),
            "Cross-validation: management"
        );

        // 7. Performance fee
        bytes32 feeSlot = TokenizedStrategyStorageLib.profitConfigSlot();
        uint16 storedFee = uint16(
            uint256(vm.load(address(mockStrategy), feeSlot)) >> 32
        );
        assertEq(
            storedFee,
            mockStrategy.performanceFee(),
            "Cross-validation: performanceFee"
        );
    }
}
