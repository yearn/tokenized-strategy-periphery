// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Clonable} from "../utils/Clonable.sol";
import {Auction} from "./Auction.sol";

contract AuctionFactory is Clonable {
    event DeployedNewAuction(address indexed auction);

    /// @notice The time that each auction lasts.
    uint256 public constant defaultAuctionCooldown = 7 days;

    /// @notice The minimum time to wait between auction 'kicks'.
    uint256 public constant defaultAuctionLength = 3 days;

    /// @notice The amount to start the auction with.
    uint256 public constant defaultStartingPrice = 1_000_000_000;

    constructor() {
        // Deploy the original
        original = address(new Auction());
    }

    function createNewAuction() external returns (address) {
        return
            _createNewAuction(
                msg.sender,
                defaultAuctionLength,
                defaultAuctionCooldown,
                defaultStartingPrice,
                address(0)
            );
    }

    function createNewAuction(address _owner) external returns (address) {
        return
            _createNewAuction(
                _owner,
                defaultAuctionLength,
                defaultAuctionCooldown,
                defaultStartingPrice,
                address(0)
            );
    }

    function createNewAuction(
        address _owner,
        address _hook
    ) external returns (address) {
        return
            _createNewAuction(
                _owner,
                defaultAuctionLength,
                defaultAuctionCooldown,
                defaultStartingPrice,
                _hook
            );
    }

    function createNewAuction(
        address _owner,
        address _hook,
        uint256 _startingPrice
    ) external returns (address) {
        return
            _createNewAuction(
                _owner,
                defaultAuctionLength,
                defaultAuctionCooldown,
                _startingPrice,
                _hook
            );
    }

    function createNewAuction(
        address _owner,
        address _hook,
        uint256 _startingPrice,
        uint256 _auctionCooldown
    ) external returns (address) {
        return
            _createNewAuction(
                _owner,
                defaultAuctionLength,
                _auctionCooldown,
                _startingPrice,
                _hook
            );
    }

    function createNewAuction(
        address _owner,
        address _hook,
        uint256 _startingPrice,
        uint256 _auctionCooldown,
        uint256 _auctionLength
    ) external returns (address) {
        return
            _createNewAuction(
                _owner,
                _auctionLength,
                _auctionCooldown,
                _startingPrice,
                _hook
            );
    }

    function _createNewAuction(
        address _owner,
        uint256 _auctionLength,
        uint256 _auctionCooldown,
        uint256 _startingPrice,
        address _hook
    ) internal returns (address _newAuction) {
        _newAuction = _clone();

        Auction(_newAuction).initialize(
            _owner,
            _auctionLength,
            _auctionCooldown,
            _startingPrice,
            _hook
        );

        emit DeployedNewAuction(_newAuction);
    }
}
