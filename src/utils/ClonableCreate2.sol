// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Clonable} from "./Clonable.sol";

contract ClonableCreate2 is Clonable {
    /**
     * @notice Clone the contracts default `original` contract using CREATE2.
     * @param salt The salt to use for deterministic deployment.
     * @return Address of the new Minimal Proxy clone.
     */
    function _cloneCreate2(bytes32 salt) internal virtual returns (address) {
        return _cloneCreate2(original, salt);
    }

    /**
     * @notice Clone any `_original` contract using CREATE2.
     * @param _original The address of the contract to clone.
     * @param salt The salt to use for deterministic deployment.
     * @return _newContract Address of the new Minimal Proxy clone.
     */
    function _cloneCreate2(
        address _original,
        bytes32 salt
    ) internal virtual returns (address _newContract) {
        // Hash the salt with msg.sender to protect deployments for specific callers
        bytes32 finalSalt = getSalt(salt, msg.sender);
        address predicted = computeCreate2Address(_original, salt, msg.sender);

        bytes20 addressBytes = bytes20(_original);
        assembly {
            // EIP-1167 bytecode
            let clone_code := mload(0x40)
            mstore(
                clone_code,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone_code, 0x14), addressBytes)
            mstore(
                add(clone_code, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            _newContract := create2(0, clone_code, 0x37, finalSalt)
        }

        require(
            _newContract != address(0) && _newContract == predicted,
            "ClonableCreate2: create2 failed"
        );
    }

    /**
     * @notice Compute the address where a clone would be deployed using CREATE2.
     * @param salt The salt to use for address computation.
     * @return The address where the clone would be deployed.
     */
    function computeCreate2Address(
        bytes32 salt
    ) external view virtual returns (address) {
        return computeCreate2Address(original, salt, msg.sender);
    }

    /**
     * @notice Compute the address where a clone would be deployed using CREATE2.
     * @param _original The address of the contract to clone.
     * @param salt The salt to use for address computation.
     * @return predicted address where the clone would be deployed.
     */
    function computeCreate2Address(
        address _original,
        bytes32 salt
    ) external view virtual returns (address predicted) {
        return computeCreate2Address(_original, salt, msg.sender);
    }

    /**
     * @notice Compute the address where a clone would be deployed using CREATE2.
     * @param _original The address of the contract to clone.
     * @param salt The salt to use for address computation.
     * @return predicted The address where the clone would be deployed.
     */
    function computeCreate2Address(
        address _original,
        bytes32 salt,
        address deployer
    ) public view virtual returns (address predicted) {
        // Hash the salt with msg.sender to match deployment behavior
        bytes32 finalSalt = getSalt(salt, deployer);

        bytes20 addressBytes = bytes20(_original);
        assembly {
            let ptr := mload(0x40)

            // Store the prefix
            mstore(
                ptr,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            // Store the address
            mstore(add(ptr, 0x14), addressBytes)
            // Store the suffix
            mstore(
                add(ptr, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )

            // Compute init code hash
            let initCodeHash := keccak256(ptr, 0x37)

            // Compute the CREATE2 address
            // 0xff ++ address(this) ++ salt ++ initCodeHash
            mstore(ptr, 0xff)
            mstore8(ptr, 0xff)
            mstore(add(ptr, 0x01), shl(96, address()))
            mstore(add(ptr, 0x15), finalSalt)
            mstore(add(ptr, 0x35), initCodeHash)

            predicted := keccak256(ptr, 0x55)
        }
    }

    /**
     * @dev Internal function to compute the final salt by hashing with msg.sender.
     * This ensures that different callers get different deployment addresses
     * even when using the same salt value.
     * @param salt The user-provided salt.
     * @return The final salt to use for CREATE2.
     */
    function getSalt(
        bytes32 salt,
        address deployer
    ) public view virtual returns (bytes32) {
        return keccak256(abi.encodePacked(salt, deployer));
    }
}
