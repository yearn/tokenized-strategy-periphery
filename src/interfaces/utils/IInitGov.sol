// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

/**
 * @title IInitGov
 * @notice Interface for the InitGov contract
 */
interface IInitGov {
    /*//////////////////////////////////////////////////////////////
                            CONSTANTS
    //////////////////////////////////////////////////////////////*/

    function SAFE() external view returns (address);

    function SIGNER_ONE() external view returns (address);

    function SIGNER_TWO() external view returns (address);

    function SIGNER_THREE() external view returns (address);

    function SIGNER_FOUR() external view returns (address);

    function SIGNER_FIVE() external view returns (address);

    function SIGNER_SIX() external view returns (address);

    function THRESHOLD() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    function isSigner(address) external view returns (bool);

    function numberSigned(bytes32) external view returns (uint256);

    function signed(address, bytes32) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                            FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Sign a transaction from an EOA
     * @param _contract The contract to transfer governance of
     * @param _newGovernance The new governance address
     */
    function signTxn(address _contract, address _newGovernance) external;

    /**
     * @notice Transfer governance (only callable by safe)
     * @param _contract The contract to transfer governance of
     * @param _newGovernance The new governance address
     */
    function transferGovernance(
        address _contract,
        address _newGovernance
    ) external;

    /**
     * @notice Get the transaction ID for a governance transfer
     * @param _contract The contract address
     * @param _newGovernance The new governance address
     * @return The transaction ID
     */
    function getTxnId(
        address _contract,
        address _newGovernance
    ) external pure returns (bytes32);
}
