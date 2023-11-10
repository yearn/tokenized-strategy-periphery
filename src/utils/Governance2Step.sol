// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Governance} from "./Governance.sol";

contract Governance2Step is Governance {
    event UpdatePendingGovernance(address indexed newPendingGovernance);

    // Address that is set to take over governance.
    address public pendingGovernance;

    constructor(address _governance) {
        governance = _governance;

        emit GovernanceTransferred(address(0), _governance);
    }

    /**
     * @notice Sets a new address as the `pendingGovernance` of the contract.
     * @dev Throws if the caller is not current governance.
     * @param _newGovernance The new governance address.
     */
    function transferGovernance(
        address _newGovernance
    ) external virtual override onlyGovernance {
        require(_newGovernance != address(0), "ZERO ADDRESS");
        pendingGovernance = _newGovernance;

        emit UpdatePendingGovernance(_newGovernance);
    }

    /**
     * @notice Allows the `pendingGovernance` to accept the role.
     */
    function acceptGovernance() external virtual {
        require(msg.sender == pendingGovernance, "!pending governance");

        emit GovernanceTransferred(governance, msg.sender);

        governance = msg.sender;
        pendingGovernance = address(0);
    }
}
