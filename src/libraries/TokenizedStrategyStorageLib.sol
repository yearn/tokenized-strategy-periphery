// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title TokenizedStrategy Storage Library
 * @author yearn.finance
 * @notice Library for accessing storage slots of TokenizedStrategy contracts
 * @dev This library provides helper functions to compute storage slot locations
 * for TokenizedStrategy state variables. This is useful for off-chain tools,
 * monitoring systems, and contracts that need direct storage access.
 *
 * Based on the pattern used by Morpho's MorphoStorageLib.
 */
library TokenizedStrategyStorageLib {
    /**
     * @dev The main storage slot for the StrategyData struct.
     * This matches the BASE_STRATEGY_STORAGE constant in TokenizedStrategy.sol
     */
    bytes32 internal constant BASE_STRATEGY_STORAGE =
        bytes32(uint256(keccak256("yearn.base.strategy.storage")) - 1);

    /**
     * @dev The StrategyData struct that holds all storage for TokenizedStrategy v3.0.4.
     * This must match the exact layout in TokenizedStrategy.sol to ensure compatibility.
     */
    struct StrategyData {
        // Slot 0: ERC20 asset (160 bits) + decimals (8 bits) + 88 bits unused
        ERC20 asset;
        uint8 decimals;
        // Slot 1: string name (dynamic storage)
        string name;
        // Slot 2: uint256 totalSupply
        uint256 totalSupply;
        // Slot 3: mapping nonces
        mapping(address => uint256) nonces;
        // Slot 4: mapping balances
        mapping(address => uint256) balances;
        // Slot 5: mapping allowances
        mapping(address => mapping(address => uint256)) allowances;
        // Slot 6: uint256 totalAssets
        uint256 totalAssets;
        // Slot 7: uint256 profitUnlockingRate
        uint256 profitUnlockingRate;
        // Slot 8: uint96 fullProfitUnlockDate (96 bits) + address keeper (160 bits)
        uint96 fullProfitUnlockDate;
        address keeper;
        // Slot 9: uint32 profitMaxUnlockTime + uint16 performanceFee + address performanceFeeRecipient (208 bits total)
        uint32 profitMaxUnlockTime;
        uint16 performanceFee;
        address performanceFeeRecipient;
        // Slot 10: uint96 lastReport + address management
        uint96 lastReport;
        address management;
        // Slot 11: address pendingManagement
        address pendingManagement;
        // Slot 12: address emergencyAdmin
        address emergencyAdmin;
        // Slot 13: uint8 entered + bool shutdown
        uint8 entered;
        bool shutdown;
    }

    /**
     * @notice Get the main storage slot for the StrategyData struct
     * @return slot The storage slot where StrategyData is stored
     */
    function strategyStorageSlot() internal pure returns (bytes32 slot) {
        return BASE_STRATEGY_STORAGE;
    }

    /**
     * @notice Get the storage slot for asset and decimals (packed)
     * @return slot The storage slot containing asset (20 bytes) and decimals (1 byte)
     */
    function assetSlot() internal pure returns (bytes32 slot) {
        return BASE_STRATEGY_STORAGE;
    }

    /**
     * @notice Get the storage slot for the strategy name
     * @return slot The storage slot for the name string
     */
    function nameSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 1);
    }

    /**
     * @notice Get the storage slot for totalSupply
     * @return slot The storage slot for totalSupply
     */
    function totalSupplySlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 2);
    }

    /**
     * @notice Get the storage slot for totalAssets
     * @return slot The storage slot for totalAssets
     */
    function totalAssetsSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 6);
    }

    /**
     * @notice Get the storage slot for profitUnlockingRate
     * @return slot The storage slot for profitUnlockingRate
     */
    function profitUnlockingRateSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 7);
    }

    /**
     * @notice Get the storage slot for fullProfitUnlockDate and keeper (packed)
     * @return slot The storage slot containing fullProfitUnlockDate (uint96) and keeper (address)
     */
    function fullProfitUnlockDateAndKeeperSlot()
        internal
        pure
        returns (bytes32 slot)
    {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 8);
    }

    /**
     * @notice Get the storage slot for profitMaxUnlockTime, performanceFee, and performanceFeeRecipient (packed)
     * @return slot The storage slot containing profitMaxUnlockTime (uint32), performanceFee (uint16), and performanceFeeRecipient (address)
     */
    function profitConfigSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 9);
    }

    /**
     * @notice Get the storage slot for lastReport and management (packed)
     * @return slot The storage slot containing lastReport (uint96) and management (address)
     */
    function lastReportAndManagementSlot()
        internal
        pure
        returns (bytes32 slot)
    {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 10);
    }

    /**
     * @notice Get the storage slot for pendingManagement
     * @return slot The storage slot for pendingManagement address
     */
    function pendingManagementSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 11);
    }

    /**
     * @notice Get the storage slot for emergencyAdmin
     * @return slot The storage slot for emergencyAdmin address
     */
    function emergencyAdminSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 12);
    }

    /**
     * @notice Get the storage slot for entered and shutdown (packed)
     * @return slot The storage slot containing entered (uint8) and shutdown (bool)
     */
    function statusSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 13);
    }

    /**
     * @notice Calculate the storage slot for a specific nonce
     * @param owner The address to get the nonce slot for
     * @return slot The storage slot for the owner's nonce
     */
    function noncesSlot(address owner) internal pure returns (bytes32 slot) {
        // nonces mapping is at slot position 3 from BASE_STRATEGY_STORAGE
        bytes32 noncesPosition = bytes32(uint256(BASE_STRATEGY_STORAGE) + 3);
        return keccak256(abi.encode(owner, noncesPosition));
    }

    /**
     * @notice Calculate the storage slot for a specific balance
     * @param account The address to get the balance slot for
     * @return slot The storage slot for the account's balance
     */
    function balancesSlot(
        address account
    ) internal pure returns (bytes32 slot) {
        // balances mapping is at slot position 4 from BASE_STRATEGY_STORAGE
        bytes32 balancesPosition = bytes32(uint256(BASE_STRATEGY_STORAGE) + 4);
        return keccak256(abi.encode(account, balancesPosition));
    }

    /**
     * @notice Calculate the storage slot for a specific allowance
     * @param owner The address that owns the tokens
     * @param spender The address that can spend the tokens
     * @return slot The storage slot for the allowance
     */
    function allowancesSlot(
        address owner,
        address spender
    ) internal pure returns (bytes32 slot) {
        // allowances mapping is at slot position 5 from BASE_STRATEGY_STORAGE
        bytes32 allowancesPosition = bytes32(
            uint256(BASE_STRATEGY_STORAGE) + 5
        );
        // For nested mappings: keccak256(spender . keccak256(owner . slot))
        bytes32 ownerSlot = keccak256(abi.encode(owner, allowancesPosition));
        return keccak256(abi.encode(spender, ownerSlot));
    }

    /**
     * @notice Helper to load the StrategyData struct from storage
     * @dev This can be used in external contracts to load the full struct
     * @return S The StrategyData struct from storage
     */
    function getStrategyStorage()
        internal
        pure
        returns (StrategyData storage S)
    {
        bytes32 slot = BASE_STRATEGY_STORAGE;
        assembly {
            S.slot := slot
        }
    }
}
