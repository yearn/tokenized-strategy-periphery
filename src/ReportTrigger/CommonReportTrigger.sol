// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

import {IVault} from "../interfaces/IVault.sol";
import {IStrategy} from "../interfaces/IStrategy.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface ICustomStrategyTrigger {
    function reportTrigger(address _strategy) external view returns (bool);
}

interface ICustomVaultTrigger {
    function reportTrigger(
        address _vault,
        address _strategy
    ) external view returns (bool);
}

interface IBaseFee {
    function basefee_global() external view returns (uint256);
}

/**
 *  @title Common Report Trigger
 *  @author Yearn.finance
 *  @dev This is a central contract that keepers can use
 *  to decide if Yearn V3 strategies should report profits as
 *  well as when a V3 Vaults should record a strategies profits.
 *
 *  It allows for a simple default flow that most strategies
 *  and vaults can use for easy integration with a keeper network.
 *  However, it is also customizable by the strategy and vaults
 *  management to allow complete customization if desired.
 */
contract CommonReportTrigger is Ownable {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event NewBaseFeeProvider(address indexed provider);

    event UpdatedAcceptableBaseFee(uint256 acceptableBaseFee);

    event UpdatedCustomStrategyTrigger(
        address indexed strategy,
        address indexed trigger
    );

    event UpdatedCustomStrategyBaseFee(
        address indexed strategy,
        uint256 acceptableBaseFee
    );

    event UpdatedCustomVaultTrigger(
        address indexed vault,
        address indexed strategy,
        address indexed trigger
    );

    event UpdatedCustomVaultBaseFee(
        address indexed vault,
        address indexed strategy,
        uint256 acceptableBaseFee
    );

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name = "Yearn Common Report Trigger";

    // Address to retreive the current base fee on the network from.
    address public baseFeeProvider;

    // Default base fee the trigger will accept for a trigger to return `true`.
    uint256 public acceptableBaseFee;

    // Mapping of a strategy address to the address of a custom report
    // trigger if the strategies management wants to implement their own
    // custom logic. If address(0) the default trigger will be used.
    mapping(address => address) public customStrategyTrigger;

    // Mapping of a strategy address to a custom base fee that will be
    // accepted for the trigger to return true. If 0 the default
    // `acceptableBaseFee` will be used.
    mapping(address => uint256) public acceptableStrategyBaseFee;

    // Mapping of a vault adddress and one of its strategies address to a
    // custom report trigger. If address(0) the default trigger will be used.
    // vaultAddress => strategyAddress => customTriggerContract.
    mapping(address => mapping(address => address)) public customVaultTrigger;

    // Mapping of a vault address and one of its strategies address to a
    // custom base fee that will be used for a trigger to return true. If
    // returns 0 then the default `acceptableBaseFee` will be used.
    // vaultAddress => strategyAddress => customBaseFee.
    mapping(address => mapping(address => uint256))
        public acceptableVaultBaseFee;

    /*//////////////////////////////////////////////////////////////
                        CUSTOM SETTERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set a custom report trigger contract for a strategy.
     * @dev This gives the `management` of a specific strategy the option
     * to enforce a custom report trigger for their strategy easily while
     * still using this standard contract for keepers to read the trigger
     * status from.
     *
     * The custom trigger contract only needs to implement the `reportTrigger`
     * function to return true or false.
     *
     * @param _strategy The address of the strategy to set the trigger for.
     * @param _trigger The address of the custom trigger contract.
     */
    function setCustomStrategyTrigger(
        address _strategy,
        address _trigger
    ) external {
        require(msg.sender == IStrategy(_strategy).management(), "!authorized");
        customStrategyTrigger[_strategy] = _trigger;

        emit UpdatedCustomStrategyTrigger(_strategy, _trigger);
    }

    /**
     * @notice Set a custom base fee for a specific strategy.
     * @dev This can be set by a strategies `management` to increase or
     * decrease the acceptable network base fee for a specific strategies
     * trigger to return true.
     *
     * This can be used instead of a custom trigger contract.
     *
     * This will have no effect if a custom trigger is set for the strategy.
     *
     * @param _strategy The address of the strategy to customize.
     * @param _baseFee The max acceptable network base fee.
     */
    function setCustomStrategyBaseFee(
        address _strategy,
        uint256 _baseFee
    ) external {
        require(msg.sender == IStrategy(_strategy).management(), "!authorized");
        acceptableStrategyBaseFee[_strategy] = _baseFee;

        emit UpdatedCustomStrategyBaseFee(_strategy, _baseFee);
    }

    /**
     * @notice Set a custom report trigger contract for a vaults strategy.
     * @dev This gives the management of a vault the option to enforce a
     * custom report trigger for a specific strategy attached to the vault
     * while still using this standard contract for keepers to read the
     * trigger status from.
     *
     * The custom trigger contract only needs to implement the `reportTrigger`
     * function to return true or false.
     *
     * @param _vault The address of the vault
     * @param _strategy The address of the strategy to set the trigger for.
     * @param _trigger The address of the custom trigger contract.
     */
    function setCustomVaultTrigger(
        address _vault,
        address _strategy,
        address _trigger
    ) external {
        // TODO: check that the address has a ADD_STRATEGY_MANAGER role
        uint256 mask = 1; // << 4;
        require(
            (IVault(_vault).roles(msg.sender) & mask) == mask,
            "!authorized"
        );
        customVaultTrigger[_vault][_strategy] = _trigger;

        emit UpdatedCustomVaultTrigger(_vault, _strategy, _trigger);
    }

    /**
     * @notice Set a custom base fee for a vaults strategy.
     * @dev This can be set by the vaults management to increase or
     * decrease the acceptable network base fee for a specific strategies
     * trigger to return true.
     *
     * This can be used instead of a custom trigger contract.
     *
     * This will have no effect if a custom trigger is set for the strategy.
     *
     * @param _vault The address of the vault.
     * @param _strategy The address of the strategy to customize.
     * @param _baseFee The max acceptable network base fee.
     */
    function setCustomVaultBaseFee(
        address _vault,
        address _strategy,
        uint256 _baseFee
    ) external {
        // TODO: check that the address has a ADD_STRATEGY_MANAGER role
        uint256 mask = 1; // << 4;
        require(
            (IVault(_vault).roles(msg.sender) & mask) == mask,
            "!authorized"
        );
        acceptableVaultBaseFee[_vault][_strategy] = _baseFee;

        emit UpdatedCustomVaultBaseFee(_vault, _strategy, _baseFee);
    }

    /*//////////////////////////////////////////////////////////////
                            TRIGGERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns wether or not a strategy is ready for a keeper to call `report`.
     * @dev Will first check if a custom trigger is set. If not it will use
     * the default trigger flow.
     *
     * This will also check if a custom acceptable base fee has been set
     * by the strategies management.
     *
     * In order for the default flow to return true the strategy must:
     *
     *   1. Not be shutdown.
     *   2. Have funds.
     *   3. The current network base fee be below the `acceptableBaseFee`.
     *   4. The time since the last report be > the strategies `profitMaxUnlockTime`.
     *
     * @param _strategy The address of the strategy to check the trigger for.
     * @return . Bool repersenting if the strategy is ready to report.
     */
    function strategyReportTrigger(
        address _strategy
    ) external view returns (bool) {
        address _trigger = customStrategyTrigger[_strategy];

        if (_trigger != address(0)) {
            return ICustomStrategyTrigger(_trigger).reportTrigger(_strategy);
        }

        IStrategy strategy = IStrategy(_strategy);

        if (strategy.isShutdown()) return false;

        if (strategy.totalAssets() == 0) return false;

        address _baseFeeProvider = baseFeeProvider;
        if (_baseFeeProvider != address(0)) {
            uint256 customAcceptableBaseFee = acceptableStrategyBaseFee[
                _strategy
            ];
            uint256 _acceptableBaseFee = customAcceptableBaseFee != 0
                ? customAcceptableBaseFee
                : acceptableBaseFee;
            if (IBaseFee(baseFeeProvider).basefee_global() > _acceptableBaseFee)
                return false;
        }

        return
            block.timestamp - strategy.lastReport() >
            strategy.profitMaxUnlockTime();
    }

    /**
     * @notice Return wether or not a report should be called on a vault for
     * a specific strategy.
     * @dev Will first check if a custom trigger is set. If not it will use
     * the default trigger flow.
     *
     * This will also check if a custom acceptable base fee has been set
     * by the vault management for the `_strategy`.
     *
     * In order for the default flow to return true:
     *
     *   1. The vault must not be shutdown.
     *   2. The strategy must be active and have debt allocated.
     *   3. The current network base fee be below the `acceptableBaseFee`.
     *   4. The time since the strategies last report be > the vaults `profitMaxUnlockTime`.
     *
     * @param _vault The address of the vault.
     * @param _strategy The address of the strategy to report.
     * @return . Bool if the strategy should report to the vault.
     */
    function vaultReportTrigger(
        address _vault,
        address _strategy
    ) external view returns (bool) {
        address _trigger = customVaultTrigger[_vault][_strategy];

        if (_trigger != address(0)) {
            return
                ICustomVaultTrigger(_trigger).reportTrigger(_vault, _strategy);
        }

        IVault vault = IVault(_vault);

        if (vault.shutdown()) return false;

        IVault.StrategyParams memory params = vault.strategies(_strategy);

        if (params.activation == 0 || params.currentDebt == 0) return false;

        address _baseFeeProvider = baseFeeProvider;
        if (_baseFeeProvider != address(0)) {
            uint256 customAcceptableBaseFee = acceptableVaultBaseFee[_vault][
                _strategy
            ];
            uint256 _acceptableBaseFee = customAcceptableBaseFee != 0
                ? customAcceptableBaseFee
                : acceptableBaseFee;
            if (IBaseFee(baseFeeProvider).basefee_global() > _acceptableBaseFee)
                return false;
        }

        return
            block.timestamp - params.lastReport > vault.profitMaxUnlockTime();
    }

    /*//////////////////////////////////////////////////////////////
                            OWNERS FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the address used to pull the current network base fee.
     * @dev Throws if the caller is not current owner.
     * @param _baseFeeProvider The network's baseFeeProvider address.
     */
    function setBaseFeeProvider(address _baseFeeProvider) external onlyOwner {
        baseFeeProvider = _baseFeeProvider;

        emit NewBaseFeeProvider(_baseFeeProvider);
    }

    /**
     * @notice Sets the default acceptable current network base fee.
     * @dev Throws if the caller is not current owner.
     * @param _newAcceptableBaseFee The acceptable network base fee.
     */
    function setAcceptableBaseFee(
        uint256 _newAcceptableBaseFee
    ) external onlyOwner {
        acceptableBaseFee = _newAcceptableBaseFee;

        emit UpdatedAcceptableBaseFee(_newAcceptableBaseFee);
    }
}
