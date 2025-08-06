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
     * @dev The StrategyData struct that holds all storage for TokenizedStrategy.
     * This must match the exact layout in TokenizedStrategy.sol to ensure compatibility.
     */
    struct StrategyData {
        // The ERC20 compliant underlying asset that will be
        // used by the Strategy
        ERC20 asset;
        // These are the corresponding ERC20 variables needed for the
        // strategies token that is issued and burned on each deposit or withdraw.
        uint8 decimals; // The amount of decimals that `asset` and strategy use.
        uint88 INITIAL_CHAIN_ID; // The initial chain id when the strategy was created.
        string name; // The name of the token for the strategy.
        uint256 totalSupply; // The total amount of shares currently issued.
        bytes32 INITIAL_DOMAIN_SEPARATOR; // The domain separator used for permits on the initial chain.
        mapping(address => uint256) nonces; // Mapping of nonces used for permit functions.
        mapping(address => uint256) balances; // Mapping to track current balances for each account that holds shares.
        mapping(address => mapping(address => uint256)) allowances; // Mapping to track the allowances for the strategies shares.
        // We manually track `totalAssets` to prevent PPS manipulation through airdrops.
        uint256 totalAssets;
        // Variables for profit reporting and locking.
        // We use uint96 for timestamps to fit in the same slot as an address. That overflows in 2.5e+21 years.
        uint256 profitUnlockingRate; // The rate at which locked profit is unlocking.
        uint96 fullProfitUnlockDate; // The timestamp at which all locked shares will unlock.
        address keeper; // Address given permission to call {report} and {tend}.
        uint32 profitMaxUnlockTime; // The amount of seconds that the reported profit unlocks over.
        uint16 performanceFee; // The percent in basis points of profit that is charged as a fee.
        address performanceFeeRecipient; // The address to pay the `performanceFee` to.
        uint96 lastReport; // The last time a {report} was called.
        // Access management variables.
        address management; // Main address that can set all configurable variables.
        address pendingManagement; // Address that is pending to take over `management`.
        address emergencyAdmin; // Address to act in emergencies as well as `management`.
        // Strategy Status
        uint8 entered; // To prevent reentrancy. Use uint8 for gas savings.
        bool shutdown; // Bool that can be used to stop deposits into the strategy.
    }

    /**
     * @notice Get the main storage slot for the StrategyData struct
     * @return slot The storage slot where StrategyData is stored
     */
    function strategyStorageSlot() internal pure returns (bytes32 slot) {
        return BASE_STRATEGY_STORAGE;
    }

    /**
     * @notice Get the storage slot for asset, decimals, and INITIAL_CHAIN_ID (packed)
     * @return slot The storage slot containing asset (20 bytes), decimals (1 byte), and INITIAL_CHAIN_ID (11 bytes)
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
     * @notice Get the storage slot for INITIAL_DOMAIN_SEPARATOR
     * @return slot The storage slot for INITIAL_DOMAIN_SEPARATOR
     */
    function initialDomainSeparatorSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 3);
    }

    /**
     * @notice Get the storage slot for totalAssets
     * @return slot The storage slot for totalAssets
     */
    function totalAssetsSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 7);
    }

    /**
     * @notice Get the storage slot for profitUnlockingRate
     * @return slot The storage slot for profitUnlockingRate
     */
    function profitUnlockingRateSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 8);
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
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 9);
    }

    /**
     * @notice Get the storage slot for profitMaxUnlockTime, performanceFee, and performanceFeeRecipient (packed)
     * @return slot The storage slot containing profitMaxUnlockTime (uint32), performanceFee (uint16), and performanceFeeRecipient (address)
     */
    function profitConfigSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 10);
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
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 11);
    }

    /**
     * @notice Get the storage slot for pendingManagement
     * @return slot The storage slot for pendingManagement address
     */
    function pendingManagementSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 12);
    }

    /**
     * @notice Get the storage slot for emergencyAdmin
     * @return slot The storage slot for emergencyAdmin address
     */
    function emergencyAdminSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 13);
    }

    /**
     * @notice Get the storage slot for entered and shutdown (packed)
     * @return slot The storage slot containing entered (uint8) and shutdown (bool)
     */
    function statusSlot() internal pure returns (bytes32 slot) {
        return bytes32(uint256(BASE_STRATEGY_STORAGE) + 14);
    }

    /**
     * @notice Calculate the storage slot for a specific nonce
     * @param owner The address to get the nonce slot for
     * @return slot The storage slot for the owner's nonce
     */
    function noncesSlot(address owner) internal pure returns (bytes32 slot) {
        // nonces mapping is at slot position 4 from BASE_STRATEGY_STORAGE
        bytes32 noncesPosition = bytes32(uint256(BASE_STRATEGY_STORAGE) + 4);
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
        // balances mapping is at slot position 5 from BASE_STRATEGY_STORAGE
        bytes32 balancesPosition = bytes32(uint256(BASE_STRATEGY_STORAGE) + 5);
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
        // allowances mapping is at slot position 6 from BASE_STRATEGY_STORAGE
        bytes32 allowancesPosition = bytes32(
            uint256(BASE_STRATEGY_STORAGE) + 6
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
