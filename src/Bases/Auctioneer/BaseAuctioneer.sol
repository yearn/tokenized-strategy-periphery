// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Auction} from "../../Auctions/Auction.sol";
import {BaseHealthCheck} from "../HealthCheck/BaseHealthCheck.sol";

/**
 *   @title Base Auctioneer
 *   @author yearn.fi
 *   @notice General use dutch auction contract for token sales.
 */
abstract contract BaseAuctioneer is BaseHealthCheck, Auction {
    /**
     * @notice Initializes the Auction contract with initial parameters.
     * @param _asset Address of the asset this auction is selling.
     * @param _name Name of the auction.
     * @param _governance Address of the contract governance.
     * @param _auctionLength Duration of each auction in seconds.
     * @param _auctionStartingPrice Starting price for each auction.
     */
    constructor(
        address _asset,
        string memory _name,
        address _governance,
        uint256 _auctionLength,
        uint256 _auctionStartingPrice
    ) BaseHealthCheck(_asset, _name) {
        initialize(
            _asset,
            address(this),
            _governance,
            _auctionLength,
            _auctionStartingPrice
        );
    }
}
