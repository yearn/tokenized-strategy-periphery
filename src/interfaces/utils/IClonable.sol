// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

/**
 * @title IClonable
 * @notice Interface for the Clonable contract
 */
interface IClonable {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set to the address to auto clone from
     * @return The original contract address to clone from
     */
    function original() external view returns (address);
}
