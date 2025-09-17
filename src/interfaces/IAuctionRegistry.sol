// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

/**
 * @title IAuctionRegistry
 * @notice Interface for the AuctionRegistry contract that manages auction factory addresses
 */
interface IAuctionRegistry {
    struct FactoryInfo {
        string version;
        uint256 index;
        bool isRetired;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Array of all registered factories
    function factories(uint256 index) external view returns (address);

    /// @notice Mapping from factory address to its info
    function factoryInfo(address factory) external view returns (string memory version, uint256 index, bool isRetired);

    /// @notice Mapping from version string to factory address
    function versionToFactory(string memory version) external view returns (address);

    /*//////////////////////////////////////////////////////////////
                            VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get the latest registered auction factory address
     * @return factory The address of the latest factory
     */
    function getLatestFactory() external view returns (address factory);

    /**
     * @notice Get a factory by its version string
     * @param _version The version string of the factory
     * @return factory The address of the factory
     */
    function getFactory(
        string memory _version
    ) external view returns (address factory);

    /**
     * @notice Get all registered factories
     * @return All factory addresses
     */
    function getAllFactories() external view returns (address[] memory);

    /**
     * @notice Get the total number of registered factories
     * @return The number of registered factories
     */
    function numberOfFactories() external view returns (uint256);

    /**
     * @notice Check if a factory is registered
     * @param _factory The address to check
     * @return True if the factory is registered
     */
    function isRegisteredFactory(address _factory) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            ADMIN METHODS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register a new factory
     * @param _factory The address of the factory
     * @param _version The version string of the factory
     */
    function registerNewFactory(
        address _factory,
        string memory _version
    ) external;

    /**
     * @notice Retire a registered factory
     * @param _factory The address of the factory
     */
    function retireFactory(address _factory) external;
}
