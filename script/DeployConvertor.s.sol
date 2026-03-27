// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./BaseScript.s.sol";
import {ConvertorFactory} from "../src/Bases/convertors/ConvertorFactory.sol";
import {Convertor4626Factory} from "../src/Bases/convertors/Convertor4626Factory.sol";

/// @notice Deploy both convertor factories and use them to deploy:
///  - the current 4626 convertor config
///  - a plain USDC -> jrUSDe convertor
/// Edit the config constants below and broadcast.
contract DeployConvertor is BaseScript {
    address internal constant MANAGEMENT =
        0x1b5f15DCb82d25f91c65b53CEe151E8b9fBdD271;
    address internal constant PERFORMANCE_FEE_RECIPIENT = 0x5A74Cb32D36f2f517DB6f7b0A0591e09b22cDE69;
    address internal constant KEEPER = 0x604e586F17cE106B64185A7a0d2c1Da5bAce711E;
    address internal constant EMERGENCY_ADMIN = 0x16388463d60FFE0661Cf7F1f31a7D658aC790ff7;

    address internal constant ASSET =
        0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    address internal constant WANT_4626 =
        0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address internal constant ORACLE_4626 =
        0x7eaC580B3F982B6BBCC929B592CED75a9E0AD287;
    address internal constant VAULT_4626 =
        0x440DA416f3Ca73EC3AE386966a090F85842C4efA;
    string internal constant NAME_4626 =
        "sUSDe/USDT Aave Looper Convertor";

    address internal constant WANT_BASE =
        0xC58D044404d8B14e953C115E67823784dEA53d8F;
    address internal constant ORACLE_BASE =
        0xfDB578391A7807891bb03BeA590d2C2409F771A2;
    string internal constant NAME_BASE = "jrUSDe Convertor";

    function run()
        external
        returns (
            address convertorFactoryDeployed,
            address convertor4626FactoryDeployed,
            address convertor4626Deployed,
            address convertorBaseDeployed
        )
    {
        vm.startBroadcast();

        ConvertorFactory convertorFactory = new ConvertorFactory(
            MANAGEMENT,
            PERFORMANCE_FEE_RECIPIENT,
            KEEPER,
            EMERGENCY_ADMIN
        );
        Convertor4626Factory convertor4626Factory = new Convertor4626Factory(
            MANAGEMENT,
            PERFORMANCE_FEE_RECIPIENT,
            KEEPER,
            EMERGENCY_ADMIN
        );

        convertor4626Deployed = convertor4626Factory.newConvertor4626(
            ASSET,
            NAME_4626,
            WANT_4626,
            ORACLE_4626,
            VAULT_4626
        );
        convertorBaseDeployed = convertorFactory.newConvertor(
            ASSET,
            NAME_BASE,
            WANT_BASE,
            ORACLE_BASE
        );

        vm.stopBroadcast();

        convertorFactoryDeployed = address(convertorFactory);
        convertor4626FactoryDeployed = address(convertor4626Factory);

        console.log("ConvertorFactory:", convertorFactoryDeployed);
        console.log("Convertor4626Factory:", convertor4626FactoryDeployed);
        console.log("management:", MANAGEMENT);
        console.log("performanceFeeRecipient:", PERFORMANCE_FEE_RECIPIENT);
        console.log("keeper:", KEEPER);
        console.log("emergencyAdmin:", EMERGENCY_ADMIN);

        console.log("4626 convertor:", convertor4626Deployed);
        console.log("4626 asset:", ASSET);
        console.log("4626 want:", WANT_4626);
        console.log("4626 oracle:", ORACLE_4626);
        console.log("4626 vault:", VAULT_4626);
        console.log(string.concat("4626 name: ", NAME_4626));

        console.log("Base convertor:", convertorBaseDeployed);
        console.log("Base asset:", ASSET);
        console.log("Base want:", WANT_BASE);
        console.log("Base oracle:", ORACLE_BASE);
        console.log(string.concat("Base name: ", NAME_BASE));
    }
}
