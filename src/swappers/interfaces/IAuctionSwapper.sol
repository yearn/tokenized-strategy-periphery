// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

interface IAuctionSwapper {
    event AuctionSet(address indexed auction);
    event UseAuctionSet(bool indexed useAuction);
    
    function auction() external view returns (address);

    function useAuction() external view returns (bool);

    function kickable(address _fromToken) external view returns (uint256);
}
