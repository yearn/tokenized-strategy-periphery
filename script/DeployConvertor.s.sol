// // SPDX-License-Identifier: AGPL-3.0
// pragma solidity >=0.8.18;

// import "./BaseScript.s.sol";
// import {ConvertorFactory} from "../src/Bases/convertors/ConvertorFactory.sol";
// import {Convertor4626Factory} from "../src/Bases/convertors/Convertor4626Factory.sol";

// /// @notice Deploy both convertor factories.
// contract DeployConvertor is BaseScript {
//     address internal constant MANAGEMENT;
//     address internal constant PERFORMANCE_FEE_RECIPIENT;
//     address internal constant KEEPER;
//     address internal constant EMERGENCY_ADMIN;

//     function run() external {
//         vm.startBroadcast();

//         ConvertorFactory convertorFactory = new ConvertorFactory(
//             MANAGEMENT,
//             PERFORMANCE_FEE_RECIPIENT,
//             KEEPER,
//             EMERGENCY_ADMIN
//         );
//         Convertor4626Factory convertor4626Factory = new Convertor4626Factory(
//             MANAGEMENT,
//             PERFORMANCE_FEE_RECIPIENT,
//             KEEPER,
//             EMERGENCY_ADMIN
//         );

//         vm.stopBroadcast();

//         console.log("ConvertorFactory:", address(convertorFactory));
//         console.log("Convertor4626Factory:", address(convertor4626Factory));
//         console.log("management:", MANAGEMENT);
//         console.log("performanceFeeRecipient:", PERFORMANCE_FEE_RECIPIENT);
//         console.log("keeper:", KEEPER);
//         console.log("emergencyAdmin:", EMERGENCY_ADMIN);
//     }
// }
