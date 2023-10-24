// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Governance} from "../utils/Governance.sol";

abstract contract AprOracleBase is Governance {
    string public name;

    constructor(
        string memory _name,
        address _governance
    ) Governance(_governance) {
        name = _name;
    }

    /**
     * @notice Will return the expected Apr of a strategy post a debt change.
     * @dev _delta is a signed integer so that it can also represent a debt
     * decrease.
     *
     * _delta will be == 0 to get the current apr.
     *
     * This will potentially be called during non-view functions so gas
     * efficiency should be taken into account.
     *
     * @param _strategy The strategy to get the apr for.
     * @param _delta The difference in debt.
     * @return . The expected apr for the strategy.
     */
    function aprAfterDebtChange(
        address _strategy,
        int256 _delta
    ) external view virtual returns (uint256);
}
