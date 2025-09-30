// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Setup, IStrategy, SafeERC20, ERC20} from "./utils/Setup.sol";
import "forge-std/console2.sol";

import {ShadowQueueAprOracle} from "../AprOracle/ShadowQueueAprOracle.sol";

contract ShadowQueueAprOracleTest is Setup {
    using SafeERC20 for ERC20;

    ShadowQueueAprOracle public oracle;

    function setUp() public override {
        super.setUp();

        oracle = new ShadowQueueAprOracle(management);
    }

    function test_crvusd_vault() public {
        // test our crvUSD vault APR before and after we update the strategies outside default queue
        address curveVault = 0xBF319dDC2Edc1Eb6FDf9910E39b37Be221C8805F;

        // check our base APR
        uint256 beforeApr = oracle.aprAfterDebtChange(curveVault, 0);
        console2.log("Default queue APR: %e", beforeApr);

        // add in the shadow queue strategies
        address[] memory toAdd = new address[](8);
        toAdd[0] = 0xf91a9A1C782a1C11B627f6E576d92C7d72CDd4AF;
        toAdd[1] = 0x2d2C784f45D9FCCE8a5bF9ebf4ee01FA6f064D1D;
        toAdd[2] = 0x75b7DB3e11138134fe4744553b5e5e3D6546d289;
        toAdd[3] = 0x6C2C45429b76406b3aAbB37b829F0B57C7badbBe;
        toAdd[4] = 0x7A26C6c1628c86788526eFB81f37a2ffac243A98;
        toAdd[5] = 0x4058dec53A72f97327dE7dD406C7E2dFD19F9a86;
        toAdd[6] = 0xBaadd4b44929606178FcDBd2f4309282f39D9dA7;
        toAdd[7] = 0x6c7150b9eb23eE563b28905791aD5B6C9cB6B21a;

        vm.prank(management);
        oracle.setExtraStrategies(curveVault, toAdd);

        // check our base APR (should be higher since we currently allocate outside default queue)
        uint256 afterApr = oracle.aprAfterDebtChange(curveVault, 0);
        console2.log("Total queue APR: %e", afterApr);

        assertGe(afterApr, beforeApr, "!extra");
    }
}
