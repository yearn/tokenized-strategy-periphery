// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface IAuctionSwapper {
    function auctionFactory() external view returns (address);

    function auction() external view returns (address);

    function kickable(address _fromToken) external view returns (uint256);
}
