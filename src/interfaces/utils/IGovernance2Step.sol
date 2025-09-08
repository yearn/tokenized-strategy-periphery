// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IGovernance} from "./IGovernance.sol";

/**
 * @title IGovernance2Step
 * @notice Interface for the Governance2Step contract
 */
interface IGovernance2Step is IGovernance {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the pending governance address is set
     * @param newPendingGovernance The new pending governance address
     */
    event UpdatePendingGovernance(address indexed newPendingGovernance);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Address that is set to take over governance
     * @return The pending governance address
     */
    function pendingGovernance() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets a new address as the `pendingGovernance` of the contract
     * @dev Throws if the caller is not current governance
     * @param _newGovernance The new governance address
     */
    function transferGovernance(address _newGovernance) external override;

    /**
     * @notice Allows the `pendingGovernance` to accept the role
     */
    function acceptGovernance() external;
}
