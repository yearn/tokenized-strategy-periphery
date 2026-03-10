// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup} from "./utils/Setup.sol";
import {MockConvertorOracle} from "./mocks/MockConvertorOracle.sol";
import {ConvertorFactory} from "../Bases/convertors/ConvertorFactory.sol";
import {IBaseConvertor} from "../Bases/convertors/IBaseConvertor.sol";

contract ConvertorFactoryTest is Setup {
    ConvertorFactory public factory;
    MockConvertorOracle public oracle;

    address public constant EMERGENCY_ADMIN = address(0xBEEF);

    function setUp() public override {
        super.setUp();

        oracle = new MockConvertorOracle();
        oracle.setPrice(1e36);

        factory = new ConvertorFactory(
            management,
            performanceFeeRecipient,
            keeper,
            EMERGENCY_ADMIN
        );
    }

    function test_newConvertor_deploysAndConfiguresStrategy() public {
        address want = tokenAddrs["USDC"];

        address deployed = factory.newConvertor(
            address(asset),
            "Factory Base Convertor",
            want,
            address(oracle)
        );

        IBaseConvertor convertor = IBaseConvertor(deployed);

        assertEq(convertor.asset(), address(asset));
        assertEq(address(convertor.WANT()), want);
        assertEq(convertor.oracle(), address(oracle));
        assertEq(convertor.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(convertor.keeper(), keeper);
        assertEq(convertor.pendingManagement(), management);
        assertEq(convertor.emergencyAdmin(), EMERGENCY_ADMIN);

        assertEq(factory.deployments(address(asset), want), deployed);
        assertTrue(factory.isDeployedConvertor(deployed));
    }

    function test_newConvertor_revertsOnDuplicateDeployment() public {
        address want = tokenAddrs["USDC"];

        address deployed = factory.newConvertor(
            address(asset),
            "Factory Base Convertor",
            want,
            address(oracle)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                ConvertorFactory.AlreadyDeployed.selector,
                deployed
            )
        );
        factory.newConvertor(
            address(asset),
            "Factory Base Convertor",
            want,
            address(oracle)
        );
    }

    function test_setAddresses_onlyManagement() public {
        vm.prank(user);
        vm.expectRevert("!management");
        factory.setAddresses(address(11), address(12), address(13));

        vm.prank(management);
        factory.setAddresses(address(11), address(12), address(13));

        assertEq(factory.management(), address(11));
        assertEq(factory.performanceFeeRecipient(), address(12));
        assertEq(factory.keeper(), address(13));
    }
}
