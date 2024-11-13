// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IBaseHealthCheck} from "../HealthCheck/IBaseHealthCheck.sol";

interface IBaseAuctioneer is IBaseHealthCheck {
    struct TokenInfo {
        address tokenAddress;
        uint96 scaler;
    }

    function auctions(
        address _from
    ) external view returns (uint64, uint64, uint128);

    function startingPrice() external view returns (uint256);

    function auctionLength() external view returns (uint256);

    function enabledAuctions(uint256) external view returns (address);

    function want() external view returns (address);

    function getAllEnabledAuctions() external view returns (address[] memory);

    function available(address _from) external view returns (uint256);

    function kickable(address _from) external view returns (uint256);

    function getAmountNeeded(
        address _from,
        uint256 _amountToTake
    ) external view returns (uint256);

    function getAmountNeeded(
        address _from,
        uint256 _amountToTake,
        uint256 _timestamp
    ) external view returns (uint256);

    function price(address _from) external view returns (uint256);

    function price(
        address _from,
        uint256 _timestamp
    ) external view returns (uint256);

    function enable(address _from) external;

    function disable(address _from) external;

    function disable(address _from, uint256 _index) external;

    function kick(address _from) external returns (uint256 available);

    function take(address _from) external returns (uint256);

    function take(address _from, uint256 _maxAmount) external returns (uint256);

    function take(
        address _from,
        uint256 _maxAmount,
        address _receiver
    ) external returns (uint256);

    function take(
        address _from,
        uint256 _maxAmount,
        address _receiver,
        bytes calldata _data
    ) external returns (uint256);

    function isValidSignature(
        bytes32 _hash,
        bytes memory _signature
    ) external view returns (bytes4);
}
