// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import "./IBaseSwapper.sol";

interface ICowSwapper is IBaseSwapper {
    event CowOrderDurationSet(uint32 indexed cowOrderDuration);
    event CowAppDataSet(bytes32 indexed cowAppData);
    event CowSettlementSet(address indexed cowSettlement);
    event CowVaultRelayerSet(address indexed cowVaultRelayer);
    event CowSwapRequested(
        bytes32 indexed orderHash,
        address indexed from,
        address indexed to,
        uint256 amountIn,
        uint256 minAmountOut,
        uint32 validTo
    );
    event CowOrderCancelled(address indexed from, bytes32 indexed orderHash);

    function cowSettlement() external view returns (address);

    function cowVaultRelayer() external view returns (address);

    function cowOrderDuration() external view returns (uint32);

    function cowAppData() external view returns (bytes32);

    function isCowOrderActive(bytes32 _orderHash) external view returns (bool);

    function activeOrder(address _from) external view returns (bytes32);

    function cowOrders(
        bytes32 _orderHash
    )
        external
        view
        returns (
            address sellToken,
            address buyToken,
            uint256 sellAmount,
            uint256 buyAmount,
            uint32 validTo
        );

    function isValidSignature(
        bytes32 _hash,
        bytes memory _signature
    ) external view returns (bytes4);
}
