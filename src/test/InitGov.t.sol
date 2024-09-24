// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "forge-std/console.sol";
import {Setup, IStrategy, SafeERC20, ERC20} from "./utils/Setup.sol";

import {AprOracle} from "../AprOracle/AprOracle.sol";
import {InitGov} from "../utils/InitGov.sol";

contract InitGovTest is Setup {
    address safe = 0x33333333D5eFb92f19a5F94a43456b3cec2797AE;

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

    InitGov public initGov;

    function setUp() public override {
        super.setUp();

        initGov = new InitGov();

        assertTrue(initGov.isSigner(SIGNER_ONE));
        assertTrue(initGov.isSigner(SIGNER_TWO));
        assertTrue(initGov.isSigner(SIGNER_THREE));
        assertTrue(initGov.isSigner(SIGNER_FOUR));
        assertTrue(initGov.isSigner(SIGNER_FIVE));
        assertTrue(initGov.isSigner(SIGNER_SIX));
    }

    function test_transferGov_withSafe() public {
        AprOracle oracle = new AprOracle(address(initGov));

        assertEq(oracle.governance(), address(initGov));

        vm.expectRevert("!safe");
        initGov.transferGovernance(address(oracle), user);

        assertEq(oracle.governance(), address(initGov));

        vm.expectRevert("!safe");
        vm.prank(SIGNER_ONE);
        initGov.transferGovernance(address(oracle), user);

        assertEq(oracle.governance(), address(initGov));

        vm.prank(safe);
        initGov.transferGovernance(address(oracle), user);

        assertEq(oracle.governance(), user);
    }

    function test_transferGov_signers() public {
        AprOracle oracle = new AprOracle(address(initGov));

        assertEq(oracle.governance(), address(initGov));

        bytes32 id = initGov.getTxnId(address(oracle), user);

        assertEq(initGov.numberSigned(id), 0);
        assertFalse(initGov.signed(SIGNER_ONE, id));
        assertFalse(initGov.signed(SIGNER_TWO, id));
        assertFalse(initGov.signed(SIGNER_THREE, id));
        assertFalse(initGov.signed(SIGNER_FOUR, id));
        assertFalse(initGov.signed(SIGNER_FIVE, id));
        assertFalse(initGov.signed(SIGNER_SIX, id));

        vm.expectRevert("!signer");
        initGov.signTxn(address(oracle), user);

        vm.prank(SIGNER_ONE);
        initGov.signTxn(address(oracle), user);

        assertEq(oracle.governance(), address(initGov));
        assertEq(initGov.numberSigned(id), 1);
        assertTrue(initGov.signed(SIGNER_ONE, id));
        assertFalse(initGov.signed(SIGNER_TWO, id));
        assertFalse(initGov.signed(SIGNER_THREE, id));
        assertFalse(initGov.signed(SIGNER_FOUR, id));
        assertFalse(initGov.signed(SIGNER_FIVE, id));
        assertFalse(initGov.signed(SIGNER_SIX, id));

        vm.expectRevert("already signed");
        vm.prank(SIGNER_ONE);
        initGov.signTxn(address(oracle), user);

        assertEq(oracle.governance(), address(initGov));
        assertEq(initGov.numberSigned(id), 1);
        assertTrue(initGov.signed(SIGNER_ONE, id));
        assertFalse(initGov.signed(SIGNER_TWO, id));
        assertFalse(initGov.signed(SIGNER_THREE, id));
        assertFalse(initGov.signed(SIGNER_FOUR, id));
        assertFalse(initGov.signed(SIGNER_FIVE, id));
        assertFalse(initGov.signed(SIGNER_SIX, id));

        vm.prank(SIGNER_FOUR);
        initGov.signTxn(address(oracle), user);

        assertEq(oracle.governance(), address(initGov));
        assertEq(initGov.numberSigned(id), 2);
        assertTrue(initGov.signed(SIGNER_ONE, id));
        assertFalse(initGov.signed(SIGNER_TWO, id));
        assertFalse(initGov.signed(SIGNER_THREE, id));
        assertTrue(initGov.signed(SIGNER_FOUR, id));
        assertFalse(initGov.signed(SIGNER_FIVE, id));
        assertFalse(initGov.signed(SIGNER_SIX, id));

        vm.prank(SIGNER_TWO);
        initGov.signTxn(address(oracle), user);

        assertEq(oracle.governance(), user);
        assertEq(initGov.numberSigned(id), 3);
        assertTrue(initGov.signed(SIGNER_ONE, id));
        assertTrue(initGov.signed(SIGNER_TWO, id));
        assertFalse(initGov.signed(SIGNER_THREE, id));
        assertTrue(initGov.signed(SIGNER_FOUR, id));
        assertFalse(initGov.signed(SIGNER_FIVE, id));
        assertFalse(initGov.signed(SIGNER_SIX, id));
    }
}
