// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IAuctionFactory} from "../interfaces/IAuctionFactory.sol";
import {Governance2Step} from "../utils/Governance2Step.sol";

/**
 * @title AuctionRegistry
 * @notice Registry contract that manages released and endorsed auction factory addresses
 * @dev Provides on-chain discovery and verification of official auction factories
 */
contract AuctionRegistry is Governance2Step {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    struct FactoryInfo {
        string version;
        uint256 index;
        bool isRetired;
    }

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    event FactoryRegistered(
        address indexed factory,
        string version,
        uint256 index
    );

    event FactoryRetired(address indexed factory);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Array of all registered factories
    address[] public factories;

    /// @notice Mapping from factory address to its index in the factories array
    mapping(address => FactoryInfo) public factoryInfo;

    /// @notice Mapping from version string to factory address
    mapping(string => address) public versionToFactory;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initialize the registry with known factory addresses
     * @param _governance The address that will have governance rights
     * @param _knownFactories Array of known factory addresses to register
     * @param _versions Array of version strings corresponding to the factories
     */
    constructor(
        address _governance,
        address[] memory _knownFactories,
        string[] memory _versions
    ) Governance2Step(_governance) {
        require(
            _knownFactories.length == _versions.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < _knownFactories.length; i++) {
            address factory = _knownFactories[i];
            if (factory.code.length > 0) {
                _registerFactory(factory, _versions[i]);
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the latest endorsed auction factory address
     * @return factory The address of the latest endorsed factory
     */
    function getLatestFactory() external view returns (address factory) {
        return factories[factories.length - 1];
    }

    /**
     * @notice Get a factory by its version string
     * @param _version The version string of the factory
     * @return factory The address of the factory
     */
    function getFactory(
        string memory _version
    ) external view returns (address factory) {
        return versionToFactory[_version];
    }

    /**
     * @notice Get factory information by address
     * @param _factory The address of the factory
     * @return info The factory information struct
     */
    function getFactoryInfo(
        address _factory
    ) external view returns (FactoryInfo memory info) {
        return factoryInfo[_factory];
    }

    /**
     * @notice Get all registered factories
     * @return All factory information
     */
    function getAllFactories() external view returns (address[] memory) {
        return factories;
    }

    /**
     * @notice Get the total number of registered factories
     * @return The number of registered factories
     */
    function numberOfFactories() external view returns (uint256) {
        return factories.length;
    }

    /**
     * @notice Check if a factory is endorsed
     * @param _factory The address to check
     * @return True if the factory is endorsed
     */
    function isRegisteredFactory(address _factory) public view returns (bool) {
        return bytes(factoryInfo[_factory].version).length > 0;
    }

    /*//////////////////////////////////////////////////////////////
                            ADMIN METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Release a new factory
     * @param _factory The address of the factory
     * @param _version The version string of the factory
     */
    function registerNewFactory(
        address _factory,
        string memory _version
    ) external onlyGovernance {
        _registerFactory(_factory, _version);
    }

    /**
     * @notice Revoke endorsement from a factory
     * @param _factory The address of the factory
     */
    function retireFactory(address _factory) external onlyGovernance {
        require(isRegisteredFactory(_factory), "Factory not registered");

        FactoryInfo storage info = factoryInfo[_factory];

        require(!info.isRetired, "Factory not retired");

        info.isRetired = true;

        emit FactoryRetired(_factory);
    }

    /*//////////////////////////////////////////////////////////////
                            INTERNAL METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @dev Internal function to register a factory
     */
    function _registerFactory(
        address _factory,
        string memory _version
    ) internal {
        require(_factory != address(0), "Invalid factory address");
        require(_factory.code.length > 0, "No code at address");
        require(!isRegisteredFactory(_factory), "Factory already registered");
        require(
            versionToFactory[_version] == address(0),
            "Version already registered"
        );

        // Verify it's a valid auction factory by checking it has the expected interface
        try IAuctionFactory(_factory).version() returns (
            string memory version_
        ) {
            require(
                keccak256(abi.encodePacked(_version)) ==
                    keccak256(abi.encodePacked(version_)),
                "Version mismatch"
            );
        } catch {}

        FactoryInfo memory info = FactoryInfo({
            version: _version,
            index: factories.length,
            isRetired: false
        });

        factories.push(_factory);
        factoryInfo[_factory] = info;
        versionToFactory[_version] = _factory;

        emit FactoryRegistered(_factory, _version, info.index);
    }
}
