// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {BaseConvertor4626} from "./BaseConvertor4626.sol";
import {IBaseConvertor4626} from "./IBaseConvertor4626.sol";

contract Convertor4626Factory {
    event NewConvertor4626(
        address indexed convertor,
        address indexed asset,
        address indexed vault,
        address want
    );
    error AlreadyDeployed(address deployed);

    address public immutable emergencyAdmin;

    address public management;
    address public performanceFeeRecipient;
    address public keeper;

    /// @notice Track 4626 convertor deployments. asset => want => vault => convertor.
    mapping(address => mapping(address => mapping(address => address)))
        public deployments4626;

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

    function newConvertor4626(
        address _asset,
        string calldata _name,
        address _want,
        address _vault,
        address _oracle
    ) external returns (address) {
        address deployed = deployments4626[_asset][_want][_vault];
        if (deployed != address(0)) revert AlreadyDeployed(deployed);

        IBaseConvertor4626 _newConvertor = IBaseConvertor4626(
            address(
                new BaseConvertor4626(_asset, _name, _want, _vault, _oracle)
            )
        );

        _configureStrategy(_newConvertor);

        deployments4626[_asset][_want][_vault] = address(_newConvertor);
        emit NewConvertor4626(address(_newConvertor), _asset, _vault, _want);

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

    function isDeployedConvertor4626(
        address _strategy
    ) external view returns (bool) {
        IBaseConvertor4626 convertor = IBaseConvertor4626(_strategy);
        return
            deployments4626[convertor.asset()][convertor.want()][
                convertor.vault()
            ] == _strategy;
    }

    function _configureStrategy(IBaseConvertor4626 _strategy) internal {
        _strategy.setPerformanceFeeRecipient(performanceFeeRecipient);
        _strategy.setKeeper(keeper);
        _strategy.setEmergencyAdmin(emergencyAdmin);
        _strategy.setPendingManagement(management);
    }
}
