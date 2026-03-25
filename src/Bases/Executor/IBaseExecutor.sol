// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IBaseHealthCheck} from "../HealthCheck/IBaseHealthCheck.sol";

/**
 * @title IBaseExecutor
 * @notice Interface for the BaseExecutor contract
 * @dev Minimal interface for generic execution functionality
 */
interface IBaseExecutor is IBaseHealthCheck {
    /*//////////////////////////////////////////////////////////////
                            STRUCTS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice A single call to execute
     * @param target The contract to call
     * @param value ETH value to send (if needed)
     * @param data The calldata to send
     */
    struct Call {
        address target;
        uint256 value;
        bytes data;
    }

    /*//////////////////////////////////////////////////////////////
                            EVENTS
    //////////////////////////////////////////////////////////////*/

    event TargetSet(address indexed target, bool allowed);
    event Executed(address indexed target, uint256 value, bool success);
    event ExecutionPaused(bool paused);
    event ExecutorSet(address indexed executor, bool allowed);

    /*//////////////////////////////////////////////////////////////
                        VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Check if a target is allowed
     * @param target The target to check
     * @return allowed Whether the target is allowed
     */
    function isAllowedTarget(
        address target
    ) external view returns (bool allowed);

    /**
     * @notice Check if execution is paused
     * @return paused Whether execution is paused
     */
    function executionPaused() external view returns (bool paused);

    /**
     * @notice Check if an executor is allowed
     * @param executor The executor to check
     * @return allowed Whether the executor is allowed
     */
    function executorIsAllowed(
        address executor
    ) external view returns (bool allowed);

    /*//////////////////////////////////////////////////////////////
                    MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set whether a target is allowed
     * @param target The target address
     * @param allowed Whether the target should be allowed
     */
    function setTarget(address target, bool allowed) external;

    /**
     * @notice Pause or unpause execution
     * @param _paused Whether to pause execution
     */
    function setExecutionPaused(bool _paused) external;

    /**
     * @notice Set whether an executor is allowed
     * @param executor The executor address
     * @param allowed Whether the executor should be allowed
     */
    function setExecutor(address executor, bool allowed) external;

    /*//////////////////////////////////////////////////////////////
                    OPERATIONAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Execute a batch of calls
     * @param calls Array of calls to execute
     * @return results Array of return data from each call
     */
    function executeBatch(Call[] calldata calls) external returns (bytes[] memory results);
}
