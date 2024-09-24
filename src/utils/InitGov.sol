// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Governance} from "./Governance.sol";

/// @notice Multi chain contract to be the initial governance for contracts on deployment.
contract InitGov {
    address public constant SAFE = 0x33333333D5eFb92f19a5F94a43456b3cec2797AE;

    address public constant SIGNER_ONE =
        0x6d2b80BA79871281Be7F70b079996a052B8D62F4;
    address public constant SIGNER_TWO =
        0x305af52AC31d3F9Daa1EC6231bA7b36Bb40f42f4;
    address public constant SIGNER_THREE =
        0xa05c4256ff0dd38697e63D48dF146e6e2FE7fe4A;
    address public constant SIGNER_FOUR =
        0x623d4A04e19328244924D1dee48252987C02fC0a;
    address public constant SIGNER_FIVE =
        0x5C166A5919cC07d785837d8Cc1261c67229d271D;
    address public constant SIGNER_SIX =
        0x80f751EdcB3012d5AF5530AFE97d5dC6EE176Bc0;

    uint256 public constant THRESHOLD = 3;

    mapping(address => bool) public isSigner;

    mapping(bytes32 => uint256) public numberSigned;

    mapping(address => mapping(bytes32 => bool)) public signed;

    constructor() {
        isSigner[SIGNER_ONE] = true;
        isSigner[SIGNER_TWO] = true;
        isSigner[SIGNER_THREE] = true;
        isSigner[SIGNER_FOUR] = true;
        isSigner[SIGNER_FIVE] = true;
        isSigner[SIGNER_SIX] = true;
    }

    /// @notice To sign a txn from an eoa.
    function signTxn(address _contract, address _newGovernance) external {
        require(isSigner[msg.sender], "!signer");
        bytes32 id = getTxnId(_contract, _newGovernance);
        require(!signed[msg.sender][id], "already signed");

        signed[msg.sender][id] = true;
        numberSigned[id] += 1;

        // Execute if we have reached the threshold.
        if (numberSigned[id] == THRESHOLD)
            _transferGovernance(_contract, _newGovernance);
    }

    /// @notice Can only be called by safe
    function transferGovernance(
        address _contract,
        address _newGovernance
    ) external {
        require(msg.sender == SAFE, "!safe");
        _transferGovernance(_contract, _newGovernance);
    }

    function _transferGovernance(
        address _contract,
        address _newGovernance
    ) internal {
        Governance(_contract).transferGovernance(_newGovernance);
    }

    function getTxnId(
        address _contract,
        address _newGovernance
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_contract, _newGovernance));
    }
}
