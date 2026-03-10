// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {BaseConvertor} from "./BaseConvertor.sol";
import {IBaseConvertor} from "./IBaseConvertor.sol";

contract ConvertorFactory {
    event NewConvertor(
        address indexed convertor,
        address indexed asset,
        address indexed want
    );
    error AlreadyDeployed(address deployed);

    address public immutable emergencyAdmin;
    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    /// @notice Track base convertor deployments. asset => want => convertor.
    mapping(address => mapping(address => address)) public deployments;

    constructor(
        address _management,
        address _performanceFeeRecipient,
        address _keeper,
        address _emergencyAdmin
    ) {
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
        emergencyAdmin = _emergencyAdmin;
    }

    function newConvertor(
        address _asset,
        string calldata _name,
        address _want,
        address _oracle
    ) external returns (address) {
        address deployed = deployments[_asset][_want];
        if (deployed != address(0)) revert AlreadyDeployed(deployed);

        IBaseConvertor _newConvertor = IBaseConvertor(
            address(new BaseConvertor(_asset, _name, _want, _oracle))
        );

        _configureStrategy(_newConvertor);

        deployments[_asset][_want] = address(_newConvertor);
        emit NewConvertor(address(_newConvertor), _asset, _want);

        return address(_newConvertor);
    }

    function setAddresses(
        address _management,
        address _performanceFeeRecipient,
        address _keeper
    ) external {
        require(msg.sender == management, "!management");
        management = _management;
        performanceFeeRecipient = _performanceFeeRecipient;
        keeper = _keeper;
    }

    function isDeployedConvertor(
        address _strategy
    ) external view returns (bool) {
        IBaseConvertor convertor = IBaseConvertor(_strategy);
        return deployments[convertor.asset()][convertor.WANT()] == _strategy;
    }

    function _configureStrategy(IBaseConvertor _strategy) internal {
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        _strategy.setKeeper(keeper);
        _strategy.setEmergencyAdmin(emergencyAdmin);
        _strategy.setPendingManagement(management);
    }
}
