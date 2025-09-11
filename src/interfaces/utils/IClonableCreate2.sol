// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IClonable} from "./IClonable.sol";

/**
 * @title IClonableCreate2
 * @notice Interface for the ClonableCreate2 contract
 */
interface IClonableCreate2 is IClonable {
    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Compute the address where a clone would be deployed using CREATE2
     * @param salt The salt to use for address computation
     * @return The address where the clone would be deployed
     */
    function computeCreate2Address(
        bytes32 salt
    ) external view returns (address);

    /**
     * @notice Compute the address where a clone would be deployed using CREATE2
     * @param _original The address of the contract to clone
     * @param salt The salt to use for address computation
     * @return predicted The address where the clone would be deployed
     */
    function computeCreate2Address(
        address _original,
        bytes32 salt
    ) external view returns (address predicted);

    /**
     * @notice Compute the address where a clone would be deployed using CREATE2
     * @param _original The address of the contract to clone
     * @param salt The salt to use for address computation
     * @param deployer The address that will deploy the clone
     * @return predicted The address where the clone would be deployed
     */
    function computeCreate2Address(
        address _original,
        bytes32 salt,
        address deployer
    ) external view returns (address predicted);

    /**
     * @notice Compute the final salt by hashing with deployer
     * @dev This ensures that different callers get different deployment addresses
     * even when using the same salt value
     * @param salt The user-provided salt
     * @param deployer The address that will deploy the clone
     * @return The final salt to use for CREATE2
     */
    function getSalt(
        bytes32 salt,
        address deployer
    ) external view returns (bytes32);
}
