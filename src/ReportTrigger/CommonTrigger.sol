// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Governance} from "../utils/Governance.sol";

import {IVault} from "@yearn-vaults/interfaces/IVault.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAuctionSwapper} from "../swappers/interfaces/IAuctionSwapper.sol";

interface ICustomStrategyTrigger {
    function reportTrigger(
        address _strategy
    ) external view returns (bool, bytes memory);
}

interface ICustomVaultTrigger {
    function reportTrigger(
        address _vault,
        address _strategy
    ) external view returns (bool, bytes memory);
}

interface ICustomAuctionTrigger {
    function auctionTrigger(
        address _strategy,
        address _from
    ) external view returns (bool, bytes memory);
}

interface IBaseFee {
    function basefee_global() external view returns (uint256);
}

/**
 *  @title Common Trigger
 *  @author Yearn.finance
 *  @dev This is a central contract that keepers can use
 *  to decide if Yearn V3 strategies should report profits,
 *  when V3 Vaults should record a strategies profits, and
 *  when strategies that implement auctions should kick off
 *  an auction.
 *
 *  It allows for a simple default flow that most strategies
 *  and vaults can use for easy integration with a keeper network.
 *  However, it is also customizable by the strategy and vaults
 *  management to allow complete customization if desired.
 */
contract CommonTrigger is Governance {
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

    event UpdatedCustomAuctionTrigger(
        address indexed strategy,
        address indexed trigger
    );

    event UpdatedMinimumAmountToKick(
        address indexed strategy,
        address indexed token,
        uint256 amount
    );

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name = "Yearn Common Trigger";

    // Address of the legacy CommonReportTrigger for fallback support
    address public constant LEGACY_REPORT_TRIGGER =
        0xA045D4dAeA28BA7Bfe234c96eAa03daFae85A147;

    // Address to retrieve the current base fee on the network from.
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
    mapping(address => uint256) public customStrategyBaseFee;

    // Mapping of a vault address and one of its strategies address to a
    // custom report trigger. If address(0) the default trigger will be used.
    // vaultAddress => strategyAddress => customTriggerContract.
    mapping(address => mapping(address => address)) public customVaultTrigger;

    // Mapping of a vault address and one of its strategies address to a
    // custom base fee that will be used for a trigger to return true. If
    // returns 0 then the default `acceptableBaseFee` will be used.
    // vaultAddress => strategyAddress => customBaseFee.
    mapping(address => mapping(address => uint256)) public customVaultBaseFee;

    // Mapping of a strategy address to the address of a custom auction
    // trigger if the strategies management wants to implement their own
    // custom logic. If address(0) the default trigger will be used.
    mapping(address => address) public customAuctionTrigger;

    // Mapping of a strategy address to a token address to minimum amount
    // strategy => token => minimum amount. Token can be address(0) for global minimum.
    mapping(address => mapping(address => uint256)) public minimumAmountToKick;

    constructor(address _governance) Governance(_governance) {}

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
    ) external virtual {
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
    ) external virtual {
        require(msg.sender == IStrategy(_strategy).management(), "!authorized");
        customStrategyBaseFee[_strategy] = _baseFee;

        emit UpdatedCustomStrategyBaseFee(_strategy, _baseFee);
    }

    /**
     * @notice Set a custom report trigger contract for a vaults strategy.
     * @dev This gives the management of a vault the option to enforce a
     * custom report trigger for a specific strategy attached to the vault
     * while still using this standard contract for keepers to read the
     * trigger status from.
     *
     * The address calling must have the `REPORTING_MANAGER` role on the vault.
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
    ) external virtual {
        // Check that the address has the REPORTING_MANAGER role on the vault.
        uint256 mask = 32;
        require((IVault(_vault).roles(msg.sender) & mask) != 0, "!authorized");
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
     * The address calling must have the `REPORTING_MANAGER` role on the vault.
     *
     * @param _vault The address of the vault.
     * @param _strategy The address of the strategy to customize.
     * @param _baseFee The max acceptable network base fee.
     */
    function setCustomVaultBaseFee(
        address _vault,
        address _strategy,
        uint256 _baseFee
    ) external virtual {
        // Check that the address has the REPORTING_MANAGER role on the vault.
        uint256 mask = 32;
        require((IVault(_vault).roles(msg.sender) & mask) != 0, "!authorized");
        customVaultBaseFee[_vault][_strategy] = _baseFee;

        emit UpdatedCustomVaultBaseFee(_vault, _strategy, _baseFee);
    }

    /**
     * @notice Set a custom auction trigger contract for a strategy.
     * @dev This gives the `management` of a specific strategy the option
     * to enforce a custom auction trigger for their strategy easily while
     * still using this standard contract for keepers to read the trigger
     * status from.
     *
     * The custom trigger contract only needs to implement the `auctionTrigger`
     * function to return true or false with bytes reason.
     *
     * @param _strategy The address of the strategy to set the trigger for.
     * @param _trigger The address of the custom trigger contract.
     */
    function setCustomAuctionTrigger(
        address _strategy,
        address _trigger
    ) external virtual {
        require(msg.sender == IStrategy(_strategy).management(), "!authorized");
        customAuctionTrigger[_strategy] = _trigger;

        emit UpdatedCustomAuctionTrigger(_strategy, _trigger);
    }

    /**
     * @notice Set a minimum amount of tokens required to kick an auction.
     * @dev This gives the `management` of a specific strategy the option
     * to set a minimum balance threshold that must be met before an
     * auction can be kicked for a specific token.
     *
     * @param _strategy The address of the strategy to set the minimum for.
     * @param _token The address of the token, or address(0) for global minimum.
     * @param _amount The minimum amount of tokens required to kick an auction.
     */
    function setMinimumAmountToKick(
        address _strategy,
        address _token,
        uint256 _amount
    ) external virtual {
        require(msg.sender == IStrategy(_strategy).management(), "!authorized");
        minimumAmountToKick[_strategy][_token] = _amount;

        emit UpdatedMinimumAmountToKick(_strategy, _token, _amount);
    }

    /*//////////////////////////////////////////////////////////////
                            TRIGGERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns wether or not a strategy is ready for a keeper to call `report`.
     * @dev Will first check if a custom trigger is set. If not it will use
     * the default trigger flow.
     *
     * @param _strategy The address of the strategy to check the trigger for.
     * @return . Bool representing if the strategy is ready to report.
     * @return . Bytes with either the calldata or reason why False.
     */
    function strategyReportTrigger(
        address _strategy
    ) external view virtual returns (bool, bytes memory) {
        address _trigger = _getCustomStrategyTrigger(_strategy);

        // If a custom trigger contract is set use that one.
        if (_trigger != address(0)) {
            return ICustomStrategyTrigger(_trigger).reportTrigger(_strategy);
        }

        // Return the default trigger logic.
        return defaultStrategyReportTrigger(_strategy);
    }

    /**
     * @notice The default trigger logic for a strategy.
     * @dev This is kept in a separate function so it can still
     * be used by custom triggers even if extra checks are needed
     * first or after.
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
     * @return . Bool representing if the strategy is ready to report.
     * @return . Bytes with either the calldata or reason why False.
     */
    function defaultStrategyReportTrigger(
        address _strategy
    ) public view virtual returns (bool, bytes memory) {
        // Cache the strategy instance.
        IStrategy strategy = IStrategy(_strategy);

        // Don't report if the strategy is shutdown.
        if (strategy.isShutdown()) return (false, bytes("Shutdown"));

        // Don't report if the strategy has no assets.
        if (strategy.totalAssets() == 0) return (false, bytes("Zero Assets"));

        // Check if a `baseFeeProvider` is set.
        address _baseFeeProvider = baseFeeProvider;
        if (_baseFeeProvider != address(0)) {
            uint256 customAcceptableBaseFee = _getCustomStrategyBaseFee(
                _strategy
            );
            // Use the custom base fee if set, otherwise use the default.
            uint256 _acceptableBaseFee = customAcceptableBaseFee != 0
                ? customAcceptableBaseFee
                : acceptableBaseFee;

            // Don't report if the base fee is to high.
            if (
                IBaseFee(_baseFeeProvider).basefee_global() > _acceptableBaseFee
            ) return (false, bytes("Base Fee"));
        }

        return (
            // Return true is the full profit unlock time has passed since the last report.
            block.timestamp - strategy.lastReport() >
                strategy.profitMaxUnlockTime(),
            // Return the report function sig as the calldata.
            abi.encodeWithSelector(strategy.report.selector)
        );
    }

    /**
     * @notice Return wether or not a report should be called on a vault for
     * a specific strategy.
     * @dev Will first check if a custom trigger is set. If not it will use
     * the default trigger flow.
     *
     * @param _vault The address of the vault.
     * @param _strategy The address of the strategy to report.
     * @return . Bool if the strategy should report to the vault.
     * @return . Bytes with either the calldata or reason why False.
     */
    function vaultReportTrigger(
        address _vault,
        address _strategy
    ) external view virtual returns (bool, bytes memory) {
        address _trigger = _getCustomVaultTrigger(_vault, _strategy);

        // If a custom trigger contract is set use that.
        if (_trigger != address(0)) {
            return
                ICustomVaultTrigger(_trigger).reportTrigger(_vault, _strategy);
        }

        // return the default trigger.
        return defaultVaultReportTrigger(_vault, _strategy);
    }

    /**
     * @notice The default trigger logic for a vault.
     * @dev This is kept in a separate function so it can still
     * be used by custom triggers even if extra checks are needed
     * before or after.
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
     * @return . Bytes with either the calldata or reason why False.
     */
    function defaultVaultReportTrigger(
        address _vault,
        address _strategy
    ) public view virtual returns (bool, bytes memory) {
        // Cache the vault instance.
        IVault vault = IVault(_vault);

        // Don't report if the vault is shutdown.
        if (vault.isShutdown()) return (false, bytes("Shutdown"));

        // Cache the strategy parameters.
        IVault.StrategyParams memory params = vault.strategies(_strategy);

        // Don't report if the strategy is not active or has no funds.
        if (params.activation == 0 || params.current_debt == 0)
            return (false, bytes("Not Active"));

        // Check if a `baseFeeProvider` is set.
        address _baseFeeProvider = baseFeeProvider;
        if (_baseFeeProvider != address(0)) {
            uint256 customAcceptableBaseFee = _getCustomVaultBaseFee(
                _vault,
                _strategy
            );
            // Use the custom base fee if set, otherwise use the default.
            uint256 _acceptableBaseFee = customAcceptableBaseFee != 0
                ? customAcceptableBaseFee
                : acceptableBaseFee;

            // Don't report if the base fee is to high.
            if (
                IBaseFee(_baseFeeProvider).basefee_global() > _acceptableBaseFee
            ) return (false, bytes("Base Fee"));
        }

        return (
            // Return true is the full profit unlock time has passed since the last report.
            block.timestamp - params.last_report > vault.profitMaxUnlockTime(),
            // Return the function selector and the strategy as the parameter to use.
            abi.encodeCall(vault.process_report, _strategy)
        );
    }

    /**
     * @notice Return whether or not a strategy should be tended by a keeper.
     * @dev This can be used as an easy keeper integration for any strategy that
     * implements a tendTrigger.
     *
     * It is expected that a strategy implement all needed checks such as
     * isShutdown, totalAssets > 0 and base fee checks within the trigger.
     *
     * @param _strategy Address of the strategy to check.
     * @return . Bool if the strategy should be tended.
     * @return . Bytes with the calldata.
     */
    function strategyTendTrigger(
        address _strategy
    ) external view virtual returns (bool, bytes memory) {
        // Return the status of the tend trigger.
        return IStrategy(_strategy).tendTrigger();
    }

    /**
     * @notice Returns the current base fee from the provider.
     * @dev Will return 0 if a base fee provider is not set.
     * @return . The current base fee for the chain.
     */
    function getCurrentBaseFee() public view virtual returns (uint256) {
        address _baseFeeProvider = baseFeeProvider;
        if (_baseFeeProvider == address(0)) return 0;

        return IBaseFee(_baseFeeProvider).basefee_global();
    }

    /**
     * @notice Returns wether or not the current base fee is acceptable
     * based on the default `acceptableBaseFee`.
     * @dev Can be used in custom triggers to easily still use this contracts
     * fee provider and acceptableBaseFee. And makes it backwards compatible to V2.
     *
     * Will always return `true` if no `baseFeeProvider` is set.
     *
     * @return . IF the current base fee is acceptable.
     */
    function isCurrentBaseFeeAcceptable() external view virtual returns (bool) {
        return getCurrentBaseFee() <= acceptableBaseFee;
    }

    /*//////////////////////////////////////////////////////////////
                        AUCTION TRIGGERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns whether or not an auction should be kicked for a strategy.
     * @dev Will first check if a custom trigger is set. If not it will
     * attempt to call `auctionTrigger` on the strategy itself. If that fails,
     * it will return false with the error message.
     *
     * This function uses try-catch to ensure it never reverts at the top level.
     *
     * @param _strategy The address of the strategy to check the trigger for.
     * @param _from The address of the token to be auctioned.
     * @return . Bool representing if the auction should be kicked.
     * @return . Bytes with either the calldata or reason why False.
     */
    function auctionTrigger(
        address _strategy,
        address _from
    ) external view virtual returns (bool, bytes memory) {
        address _trigger = _getCustomAuctionTrigger(_strategy);

        // If a custom trigger contract is set use that one.
        if (_trigger != address(0)) {
            // Use try-catch to handle any reverts in the custom trigger
            try
                ICustomAuctionTrigger(_trigger).auctionTrigger(_strategy, _from)
            returns (bool shouldKick, bytes memory data) {
                return (shouldKick, data);
            } catch {} // If it fails, try the default trigger path
        }

        // Return the default trigger logic.
        return defaultAuctionTrigger(_strategy, _from);
    }

    /**
     * @notice The default trigger logic for a strategy auction.
     * @dev This attempts to call `auctionTrigger(address)` on the strategy itself.
     * If the strategy implements this function, it will use that logic.
     * If not, or if it reverts, it will return false.
     *
     * This will also check if a custom acceptable base fee has been set
     * by the strategies management.
     *
     * @param _strategy The address of the strategy to check the trigger for.
     * @param _from The address of the token to be auctioned.
     * @return . Bool representing if the auction should be kicked.
     * @return . Bytes with either the calldata or reason why False.
     */
    function defaultAuctionTrigger(
        address _strategy,
        address _from
    ) public view virtual returns (bool, bytes memory) {
        // Check if a `baseFeeProvider` is set and if base fee is acceptable.
        address _baseFeeProvider = baseFeeProvider;
        if (_baseFeeProvider != address(0)) {
            uint256 customAcceptableBaseFee = _getCustomStrategyBaseFee(
                _strategy
            );
            // Use the custom base fee if set, otherwise use the default.
            uint256 _acceptableBaseFee = customAcceptableBaseFee != 0
                ? customAcceptableBaseFee
                : acceptableBaseFee;

            // Don't trigger if the base fee is too high.
            if (
                IBaseFee(_baseFeeProvider).basefee_global() > _acceptableBaseFee
            ) return (false, bytes("Base Fee"));
        }

        // Check if minimum amount to kick is met
        uint256 minimumAmount = _getMinimumAmountToKick(_strategy, _from);
        if (minimumAmount > 0) {
            uint256 balance = ERC20(_from).balanceOf(_strategy);
            if (balance > minimumAmount) {
                return (
                    true,
                    abi.encodeCall(
                        IAuctionSwapper(_strategy).kickAuction,
                        (_from)
                    )
                );
            }
        }

        // Try to call auctionTrigger on the strategy itself
        // Use try-catch to handle strategies that don't implement it or revert
        try IAuctionSwapper(_strategy).auctionTrigger(_from) returns (
            bool shouldKick,
            bytes memory data
        ) {
            return (shouldKick, data);
        } catch {
            // If the call fails (strategy doesn't implement it or reverts),
            // return false with a descriptive message
            return (
                false,
                bytes("Strategy trigger not implemented or reverted")
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                    LEGACY FALLBACK HELPERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to get custom strategy trigger with legacy fallback.
     */
    function _getCustomStrategyTrigger(
        address _strategy
    ) internal view returns (address) {
        address trigger = customStrategyTrigger[_strategy];

        // If not set locally, check legacy contract
        if (trigger == address(0)) {
            bytes memory data = _getFromLegacy(
                abi.encodeCall(
                    CommonTrigger(LEGACY_REPORT_TRIGGER).customStrategyTrigger,
                    (_strategy)
                )
            );
            if (data.length > 0) {
                trigger = abi.decode(data, (address));
            }
        }

        return trigger;
    }

    /**
     * @dev Internal function to get custom strategy base fee with legacy fallback.
     */
    function _getCustomStrategyBaseFee(
        address _strategy
    ) internal view returns (uint256) {
        uint256 baseFee = customStrategyBaseFee[_strategy];

        // If not set locally, check legacy contract
        if (baseFee == 0) {
            bytes memory data = _getFromLegacy(
                abi.encodeCall(
                    CommonTrigger(LEGACY_REPORT_TRIGGER).customStrategyBaseFee,
                    (_strategy)
                )
            );
            if (data.length > 0) {
                baseFee = abi.decode(data, (uint256));
            }
        }

        return baseFee;
    }

    /**
     * @dev Internal function to get custom vault trigger with legacy fallback.
     */
    function _getCustomVaultTrigger(
        address _vault,
        address _strategy
    ) internal view returns (address) {
        address trigger = customVaultTrigger[_vault][_strategy];

        // If not set locally, check legacy contract
        if (trigger == address(0)) {
            bytes memory data = _getFromLegacy(
                abi.encodeCall(
                    CommonTrigger(LEGACY_REPORT_TRIGGER).customVaultTrigger,
                    (_vault, _strategy)
                )
            );
            if (data.length > 0) {
                trigger = abi.decode(data, (address));
            }
        }

        return trigger;
    }

    /**
     * @dev Internal function to get custom vault base fee with legacy fallback.
     */
    function _getCustomVaultBaseFee(
        address _vault,
        address _strategy
    ) internal view returns (uint256) {
        uint256 baseFee = customVaultBaseFee[_vault][_strategy];

        // If not set locally, check legacy contract
        if (baseFee == 0) {
            bytes memory data = _getFromLegacy(
                abi.encodeCall(
                    CommonTrigger(LEGACY_REPORT_TRIGGER).customVaultBaseFee,
                    (_vault, _strategy)
                )
            );
            if (data.length > 0) {
                baseFee = abi.decode(data, (uint256));
            }
        }

        return baseFee;
    }

    function _getFromLegacy(
        bytes memory _data
    ) internal view returns (bytes memory) {
        (bool success, bytes memory data) = LEGACY_REPORT_TRIGGER.staticcall(
            _data
        );
        if (success && data.length > 0) {
            return data;
        }
        return bytes("");
    }

    /**
     * @dev Internal function to get custom auction trigger - no legacy fallback since this is new.
     */
    function _getCustomAuctionTrigger(
        address _strategy
    ) internal view returns (address) {
        return customAuctionTrigger[_strategy];
    }

    /**
     * @dev Internal function to get minimum amount to kick for a strategy-token pair.
     * First checks for specific token minimum, then falls back to global minimum.
     */
    function _getMinimumAmountToKick(
        address _strategy,
        address _token
    ) internal view returns (uint256) {
        // Check for specific token minimum
        uint256 specificMinimum = minimumAmountToKick[_strategy][_token];
        if (specificMinimum > 0) {
            return specificMinimum;
        }

        // Fall back to global minimum (address(0))
        return minimumAmountToKick[_strategy][address(0)];
    }

    /*//////////////////////////////////////////////////////////////
                        GOVERNANCE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets the address used to pull the current network base fee.
     * @dev Throws if the caller is not current governance.
     * @param _baseFeeProvider The network's baseFeeProvider address.
     */
    function setBaseFeeProvider(
        address _baseFeeProvider
    ) external virtual onlyGovernance {
        baseFeeProvider = _baseFeeProvider;

        emit NewBaseFeeProvider(_baseFeeProvider);
    }

    /**
     * @notice Sets the default acceptable current network base fee.
     * @dev Throws if the caller is not current governance.
     * @param _newAcceptableBaseFee The acceptable network base fee.
     */
    function setAcceptableBaseFee(
        uint256 _newAcceptableBaseFee
    ) external virtual onlyGovernance {
        acceptableBaseFee = _newAcceptableBaseFee;

        emit UpdatedAcceptableBaseFee(_newAcceptableBaseFee);
    }
}
