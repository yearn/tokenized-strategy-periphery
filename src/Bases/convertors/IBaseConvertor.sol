// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IBaseHealthCheck} from "../HealthCheck/IBaseHealthCheck.sol";

interface IBaseConvertor is IBaseHealthCheck {
    function want() external view returns (address);

    function sellAssetAuction() external view returns (address);

    function buyAssetAuction() external view returns (address);

    function oracle() external view returns (address);

    function maxSlippageBps() external view returns (uint16);

    function startingPriceBps() external view returns (uint16);

    function decayRate() external view returns (uint256);

    function reportBuffer() external view returns (uint16);

    function setOracle(address _oracle) external;

    function setMaxSlippageBps(uint16 _maxSlippageBps) external;

    function setStartingPriceBps(uint16 _startingPriceBps) external;

    function setDecayRate(uint256 _decayRate) external;

    function setReportBuffer(uint16 _reportBuffer) external;

    function setAuctionStepDecayRate(
        address _from,
        uint256 _stepDecayRate
    ) external;

    function setAuctionStepDuration(
        address _from,
        uint256 _stepDuration
    ) external;

    function enableAuctionToken(address _from) external;

    function sweepAuctionToken(address _from, address _token) external;

    function kickAuction(address _from) external returns (uint256);

    function kickable(address _from) external view returns (uint256);

    function auctionTrigger(
        address _from
    ) external view returns (bool shouldKick, bytes memory data);

    function balanceOfAsset() external view returns (uint256);

    function balanceOfWant() external view returns (uint256);

    function balanceOfAssetInAuction() external view returns (uint256);

    function balanceOfWantInAuction() external view returns (uint256);
}
