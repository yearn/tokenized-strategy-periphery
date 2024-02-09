// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Clonable} from "../utils/Clonable.sol";
import {Auction} from "./Auction.sol";

contract AuctionFactory is Clonable {
    event DeployedNewAuction(address indexed auction);

    /// @notice The time that each auction lasts.
    uint256 public constant defaultAuctionLength = 1 days;

    /// @notice The minimum time to wait between auction 'kicks'.
    uint256 public constant defaultAuctionCooldown = 5 days;

    /// @notice The amount to start the auction with.
    uint256 public constant defaultStartingPrice = 1_000_000;

    constructor() {
        // Deploy the original
        original = address(new Auction());
    }

    function createNewAuction(address _want) external returns (address) {
        return
            _createNewAuction(
                _want,
                address(0),
                msg.sender,
                defaultAuctionLength,
                defaultAuctionCooldown,
                defaultStartingPrice
            );
    }

    function createNewAuction(
        address _want,
        address _hook
    ) external returns (address) {
        return
            _createNewAuction(
                _want,
                _hook,
                msg.sender,
                defaultAuctionLength,
                defaultAuctionCooldown,
                defaultStartingPrice
            );
    }

    function createNewAuction(
        address _want,
        address _hook,
        address _governance
    ) external returns (address) {
        return
            _createNewAuction(
                _want,
                _hook,
                _governance,
                defaultAuctionLength,
                defaultAuctionCooldown,
                defaultStartingPrice
            );
    }

    function createNewAuction(
        address _want,
        address _hook,
        address _governance,
        uint256 _auctionLength
    ) external returns (address) {
        return
            _createNewAuction(
                _want,
                _hook,
                _governance,
                _auctionLength,
                defaultAuctionCooldown,
                defaultStartingPrice
            );
    }

    function createNewAuction(
        address _want,
        address _hook,
        address _governance,
        uint256 _auctionLength,
        uint256 _auctionCooldown
    ) external returns (address) {
        return
            _createNewAuction(
                _want,
                _hook,
                _governance,
                _auctionLength,
                _auctionCooldown,
                defaultStartingPrice
            );
    }

    function createNewAuction(
        address _want,
        address _hook,
        address _governance,
        uint256 _auctionLength,
        uint256 _auctionCooldown,
        uint256 _startingPrice
    ) external returns (address) {
        return
            _createNewAuction(
                _want,
                _hook,
                _governance,
                _auctionLength,
                _auctionCooldown,
                _startingPrice
            );
    }

    function _createNewAuction(
        address _want,
        address _hook,
        address _governance,
        uint256 _auctionLength,
        uint256 _auctionCooldown,
        uint256 _startingPrice
    ) internal returns (address _newAuction) {
        _newAuction = _clone();

        Auction(_newAuction).initialize(
            _want,
            _hook,
            _governance,
            _auctionLength,
            _auctionCooldown,
            _startingPrice
        );

        emit DeployedNewAuction(_newAuction);
    }
}
