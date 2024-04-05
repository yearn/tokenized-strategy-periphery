// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface IAuctionSwapper {
    function auctionFactory() external view returns (address);

    function auction() external view returns (address);

    function kickable(address _fromToken) external view returns (uint256);

    function auctionKicked(address _fromToken) external returns (uint256);

    function preTake(address _fromToken, uint256 _amountToTake) external;

    function postTake(address _toToken, uint256 _newAmount) external;
}
