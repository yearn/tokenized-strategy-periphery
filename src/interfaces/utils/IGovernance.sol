// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

/**
 * @title IGovernance
 * @notice Interface for the Governance contract
 */
interface IGovernance {
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Emitted when the governance address is updated
     * @param previousGovernance The previous governance address
     * @param newGovernance The new governance address
     */
    event GovernanceTransferred(
        address indexed previousGovernance,
        address indexed newGovernance
    );

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Address that can set the default base fee and provider
     * @return The current governance address
     */
    function governance() external view returns (address);

    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sets a new address as the governance of the contract
     * @dev Throws if the caller is not current governance
     * @param _newGovernance The new governance address
     */
    function transferGovernance(address _newGovernance) external;
}
