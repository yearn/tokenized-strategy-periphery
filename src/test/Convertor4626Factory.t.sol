// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup} from "./utils/Setup.sol";
import {MockStrategy} from "./mocks/MockStrategy.sol";
import {MockConvertorOracle} from "./mocks/MockConvertorOracle.sol";
import {Convertor4626Factory} from "../Bases/convertors/Convertor4626Factory.sol";
import {IBaseConvertor4626} from "../Bases/convertors/IBaseConvertor4626.sol";

contract Convertor4626FactoryTest is Setup {
    Convertor4626Factory public factory;
    MockConvertorOracle public oracle;

    address public constant EMERGENCY_ADMIN = address(0xBEEF);

    function setUp() public override {
        super.setUp();

        oracle = new MockConvertorOracle();
        oracle.setPrice(1e36);

        factory = new Convertor4626Factory(
            management,
            performanceFeeRecipient,
            keeper,
            EMERGENCY_ADMIN
        );
    }

    function test_newConvertor4626_deploysAndConfiguresStrategy() public {
        address want = tokenAddrs["USDC"];
        MockStrategy vault = new MockStrategy(want);

        address deployed = factory.newConvertor4626(
            address(asset),
            "Factory 4626 Convertor",
            want,
            address(oracle),
            address(vault)
        );

        IBaseConvertor4626 convertor = IBaseConvertor4626(deployed);

        assertEq(convertor.asset(), address(asset));
        assertEq(address(convertor.WANT()), want);
        assertEq(convertor.oracle(), address(oracle));
        assertEq(address(convertor.vault()), address(vault));
        assertEq(convertor.performanceFeeRecipient(), performanceFeeRecipient);
        assertEq(convertor.keeper(), keeper);
        assertEq(convertor.pendingManagement(), management);
        assertEq(convertor.emergencyAdmin(), EMERGENCY_ADMIN);

        assertEq(
            factory.deployments4626(address(asset), want, address(vault)),
            deployed
        );
        assertTrue(factory.isDeployedConvertor4626(deployed));
    }

    function test_newConvertor4626_revertsOnDuplicateDeployment() public {
        address want = tokenAddrs["USDC"];
        MockStrategy vault = new MockStrategy(want);

        address deployed = factory.newConvertor4626(
            address(asset),
            "Factory 4626 Convertor",
            want,
            address(oracle),
            address(vault)
        );

        vm.expectRevert(
            abi.encodeWithSelector(
                Convertor4626Factory.AlreadyDeployed.selector,
                deployed
            )
        );
        factory.newConvertor4626(
            address(asset),
            "Factory 4626 Convertor",
            want,
            address(oracle),
            address(vault)
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
