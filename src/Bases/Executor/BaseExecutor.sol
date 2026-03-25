// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {BaseHealthCheck} from "../HealthCheck/BaseHealthCheck.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title BaseExecutor
 * @author Yearn.fi
 * @notice Minimal base contract for strategies that need arbitrary execution capabilities
 * @dev Provides generic execution functions with customizable verification hooks.
 *      All verification logic is left to inheriting contracts.
 */
abstract contract BaseExecutor is BaseHealthCheck, ReentrancyGuard {
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
                            MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Ensures execution is not paused
     */
    modifier whenNotPaused() {
        require(!executionPaused, "execution paused");
        _;
    }

    modifier onlyExecutor() {
        _onlyExecutor();
        _;
    }

    /**
     * @notice Require that the msg.sender is the executor
     */
    function _onlyExecutor() internal view {
        require(
            executorIsAllowed[msg.sender] ||
                msg.sender == TokenizedStrategy.management(),
            "!executor"
        );
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of allowed execution targets
    mapping(address => bool) public isAllowedTarget;

    mapping(address => bool) public executorIsAllowed;

    /// @notice Whether execution is currently paused
    bool public executionPaused;

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _asset,
        string memory _name
    ) BaseHealthCheck(_asset, _name) {}

    /*//////////////////////////////////////////////////////////////
                        EXECUTION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function executeBatch(
        Call[] calldata calls
    )
        external
        virtual
        whenNotPaused
        nonReentrant
        onlyExecutor
        returns (bytes[] memory results)
    {
        return _executeBatch(calls);
    }

    /**
     * @notice Execute multiple calls in sequence
     * @param calls Array of calls to execute
     * @return results Array of return data from each call
     */
    function _executeBatch(
        Call[] calldata calls
    ) internal virtual returns (bytes[] memory results) {
        require(calls.length > 0, "empty batch");

        // Pre-batch hook
        _beforeBatch(calls);

        results = new bytes[](calls.length);

        for (uint256 i = 0; i < calls.length; i++) {
            (bool success, bytes memory result) = _executeWithValue(
                calls[i].target,
                calls[i].value,
                calls[i].data
            );

            results[i] = result;
        }

        // Post-batch hook
        _afterBatch(calls, results);

        return results;
    }

    /**
     * @notice Execute a single call with ETH value
     * @param target The contract to call
     * @param value ETH value to send
     * @param data The calldata to send
     * @return success Whether the call succeeded
     * @return result The return data from the call
     */
    function _executeWithValue(
        address target,
        uint256 value,
        bytes calldata data
    )
        internal
        virtual
        whenNotPaused
        nonReentrant
        returns (bool success, bytes memory result)
    {
        // Check if target is allowed
        _validateCallData(target, value, data);

        // Pre-execution hook
        _beforeExecute(target, value, data);

        // Perform the external call
        (success, result) = target.call{value: value}(data);

        if (!success && !_shouldContinueOnFailure(target, value, data)) {
            revert("execution failed");
        }

        // Post-execution hook
        _afterExecute(target, value, data, success, result);

        emit Executed(target, value, success);

        return (success, result);
    }

    /*//////////////////////////////////////////////////////////////
                        HOOKS (TO BE OVERRIDDEN)
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Hook called before a single execution
     * @dev Override to add pre-execution checks or state changes
     * @param target The target being called
     * @param . ETH value being sent
     * @param . Calldata being sent
     */
    function _validateCallData(
        address target,
        uint256,
        bytes calldata
    ) internal virtual {
        require(isAllowedTarget[target], "target not allowed");
    }

    /**
     * @notice Hook called before a single execution
     * @dev Override to add pre-execution checks or state changes
     * @param target The target being called
     * @param value ETH value being sent
     * @param data Calldata being sent
     */
    function _beforeExecute(
        address target,
        uint256 value,
        bytes calldata data
    ) internal virtual {}

    /**
     * @notice Hook called after a single execution
     * @dev Override to add post-execution verification or state updates
     * @param target The target that was called
     * @param value ETH value that was sent
     * @param data Calldata that was sent
     * @param success Whether the call succeeded
     * @param result The return data
     */
    function _afterExecute(
        address target,
        uint256 value,
        bytes calldata data,
        bool success,
        bytes memory result
    ) internal virtual {}

    /**
     * @notice Hook called before a batch execution
     * @dev Override to add pre-batch verification
     * @param calls The array of calls to be executed
     */
    function _beforeBatch(Call[] calldata calls) internal virtual {}

    /**
     * @notice Hook called after a batch execution
     * @dev Override to add post-batch verification
     * @param calls The array of calls that were executed
     * @param results The results from each call
     */
    function _afterBatch(
        Call[] calldata calls,
        bytes[] memory results
    ) internal virtual {}

    /**
     * @notice Determines if batch should continue after a failure
     * @dev Override to implement custom failure handling
     * @param target The target that failed
     * @param value The value that failed
     * @param data The data that failed
     * @return Whether to continue execution
     */
    function _shouldContinueOnFailure(
        address target,
        uint256 value,
        bytes calldata data
    ) internal view virtual returns (bool) {
        // Default: stop on any failure
        return false;
    }

    /*//////////////////////////////////////////////////////////////
                    MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Set whether a target is allowed
     * @param target The target address
     * @param allowed Whether the target should be allowed
     */
    function setTarget(
        address target,
        bool allowed
    ) external virtual onlyManagement {
        require(
            target != address(0) && target != address(this),
            "invalid target"
        );
        isAllowedTarget[target] = allowed;
        emit TargetSet(target, allowed);
    }

    /**
     * @notice Pause or unpause execution
     * @param _paused Whether to pause execution
     */
    function setExecutionPaused(
        bool _paused
    ) external virtual onlyEmergencyAuthorized {
        executionPaused = _paused;
        emit ExecutionPaused(_paused);
    }

    /**
     * @notice Set whether an executor is allowed
     * @param executor The executor address
     * @param allowed Whether the executor should be allowed
     */
    function setExecutor(
        address executor,
        bool allowed
    ) external virtual onlyManagement {
        executorIsAllowed[executor] = allowed;
        emit ExecutorSet(executor, allowed);
    }
}
