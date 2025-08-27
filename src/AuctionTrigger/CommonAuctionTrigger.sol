// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Governance} from "../utils/Governance.sol";
import {IStrategy} from "@tokenized-strategy/interfaces/IStrategy.sol";

interface ICustomAuctionTrigger {
    function auctionTrigger(
        address _strategy,
        address _from
    ) external view returns (bool, bytes memory);
}

interface IStrategyAuctionTrigger {
    function auctionTrigger(
        address _from
    ) external view returns (bool, bytes memory);
}

interface IBaseFee {
    function basefee_global() external view returns (uint256);
}

/**
 *  @title Common Auction Trigger
 *  @author Yearn.finance
 *  @dev This is a central contract that keepers can use
 *  to decide if strategies that implement auctions should
 *  kick off an auction.
 *
 *  It allows for a simple default flow that most strategies
 *  can use for easy integration with a keeper network.
 *  However, it is also customizable by the strategy's
 *  management to allow complete customization if desired.
 */
contract CommonAuctionTrigger is Governance {
    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                            STORAGE
    //////////////////////////////////////////////////////////////*/

    string public name = "Yearn Common Auction Trigger";

    // Address to retrieve the current base fee on the network from.
    address public baseFeeProvider;

    // Default base fee the trigger will accept for a trigger to return `true`.
    uint256 public acceptableBaseFee;

    // Mapping of a strategy address to the address of a custom auction
    // trigger if the strategies management wants to implement their own
    // custom logic. If address(0) the default trigger will be used.
    mapping(address => address) public customAuctionTrigger;

    // Mapping of a strategy address to a custom base fee that will be
    // accepted for the trigger to return true. If 0 the default
    // `acceptableBaseFee` will be used.
    mapping(address => uint256) public customStrategyBaseFee;

    constructor(address _governance) Governance(_governance) {}

    /*//////////////////////////////////////////////////////////////
                        CUSTOM SETTERS
    //////////////////////////////////////////////////////////////*/

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

    /*//////////////////////////////////////////////////////////////
                            TRIGGERS
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
        address _trigger = customAuctionTrigger[_strategy];

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
            uint256 customAcceptableBaseFee = customStrategyBaseFee[_strategy];
            // Use the custom base fee if set, otherwise use the default.
            uint256 _acceptableBaseFee = customAcceptableBaseFee != 0
                ? customAcceptableBaseFee
                : acceptableBaseFee;

            // Don't trigger if the base fee is too high.
            if (
                IBaseFee(_baseFeeProvider).basefee_global() > _acceptableBaseFee
            ) return (false, bytes("Base Fee"));
        }

        // Try to call auctionTrigger on the strategy itself
        // Use try-catch to handle strategies that don't implement it or revert
        try IStrategyAuctionTrigger(_strategy).auctionTrigger(_from) returns (
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
     * @notice Returns whether or not the current base fee is acceptable
     * based on the default `acceptableBaseFee`.
     * @dev Can be used in custom triggers to easily still use this contracts
     * fee provider and acceptableBaseFee.
     *
     * Will always return `true` if no `baseFeeProvider` is set.
     *
     * @return . IF the current base fee is acceptable.
     */
    function isCurrentBaseFeeAcceptable() external view virtual returns (bool) {
        return getCurrentBaseFee() <= acceptableBaseFee;
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
