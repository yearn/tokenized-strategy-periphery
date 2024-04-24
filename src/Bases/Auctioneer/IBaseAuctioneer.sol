// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IBaseHealthCheck} from "../HealthCheck/IBaseHealthCheck.sol";

interface IBaseAuctioneer is IBaseHealthCheck {
    struct TokenInfo {
        address tokenAddress;
        uint96 scaler;
    }

    function auctionStartingPrice() external view returns (uint256);

    function auctionLength() external view returns (uint32);

    function auctionCooldown() external view returns (uint32);

    function auctions(
        bytes32
    )
        external
        view
        returns (
            TokenInfo memory fromInfo,
            uint96 kicked,
            uint128 initialAvailable,
            uint128 currentAvailable
        );

    function enabledAuctions() external view returns (bytes32[] memory);

    function auctionWant() external view returns (address);

    function numberOfEnabledAuctions() external view returns (uint256);

    function getAuctionId(address _from) external view returns (bytes32);

    function auctionInfo(
        bytes32 _auctionId
    )
        external
        view
        returns (
            address _from,
            address _to,
            uint256 _kicked,
            uint256 _available
        );

    function kickable(bytes32 _auctionId) external view returns (uint256);

    function getAmountNeeded(
        bytes32 _auctionId,
        uint256 _amountToTake
    ) external view returns (uint256);

    function getAmountNeeded(
        bytes32 _auctionId,
        uint256 _amountToTake,
        uint256 _timestamp
    ) external view returns (uint256);

    function price(bytes32 _auctionId) external view returns (uint256);

    function price(
        bytes32 _auctionId,
        uint256 _timestamp
    ) external view returns (uint256);

    function enableAuction(address _from) external returns (bytes32);

    function disableAuction(address _from) external;

    function disableAuction(address _from, uint256 _index) external;

    function kick(bytes32 _auctionId) external returns (uint256 available);

    function take(bytes32 _auctionId) external returns (uint256);

    function take(
        bytes32 _auctionId,
        uint256 _maxAmount
    ) external returns (uint256);

    function take(
        bytes32 _auctionId,
        uint256 _maxAmount,
        address _receiver
    ) external returns (uint256);

    function take(
        bytes32 _auctionId,
        uint256 _maxAmount,
        address _receiver,
        bytes calldata _data
    ) external returns (uint256);
}
