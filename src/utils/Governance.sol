// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.18;

contract Governance {
    event GovernanceTransferred(
        address indexed previousGovernance,
        address indexed newGovernance
    );

    modifier onlyGovernance() {
        _checkGovernance();
        _;
    }

    function _checkGovernance() internal view virtual {
        require(governance == msg.sender, "!governance");
    }

    // Address that can set the defualt base fee and provider
    address public governance;

    constructor(address _governance) {
        governance = _governance;

        emit GovernanceTransferred(address(0), _governance);
    }

    /**
     * @notice Sets a new address as the governance of the contract.
     * @dev Throws if the caller is not current governance.
     * @param _newGovernance The new governance address.
     */
    function transferGovernance(
        address _newGovernance
    ) external onlyGovernance {
        require(_newGovernance != address(0), "ZERO ADDRESS");
        address oldGovernance = governance;
        governance = _newGovernance;

        emit GovernanceTransferred(oldGovernance, _newGovernance);
    }
}
