// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./BaseScript.s.sol";
import {BaseConvertor} from "../src/Bases/convertors/BaseConvertor.sol";

/// @notice Deploy BaseConvertor with constructor params from env vars.
/// @dev Required env:
///  - ASSET (address)
///  - WANT (address)
///  - ORACLE (address)
///  - NAME (string)
contract DeployConvertor is BaseScript {
    address asset = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
    address want = 0xC9d24aD0bB25F34098e226a8C5192Dea7bacccaE;
    address oracle = 0x2252b2910f2A584C66E6215f31DBEDcC37b32AA9;
    string name = "USDai June 18th PT Convertor";

    function run() external returns (address deployed) {
        
        vm.startBroadcast();
        BaseConvertor convertor = new BaseConvertor(
            asset,
            name,
            want,
            oracle
        );
        vm.stopBroadcast();

        deployed = address(convertor);

        console.log("BaseConvertor deployed:", deployed);
        console.log("asset:", asset);
        console.log("want:", want);
        console.log("oracle:", oracle);
        console.log("name:", name);
    }
}
