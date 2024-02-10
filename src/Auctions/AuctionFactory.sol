// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Clonable} from "../utils/Clonable.sol";
import {Auction} from "./Auction.sol";

/// @title AuctionFactory
/// @notice Deploy a new Auction.
contract AuctionFactory is Clonable {
    event DeployedNewAuction(address indexed auction, address indexed want);

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

    /**
     * @notice Creates a new auction contract.
     * @param _want Address of the token users will bid with.
     * @return _newAuction Address of the newly created auction contract.
     */
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

    /**
     * @notice Creates a new auction contract.
     * @param _want Address of the token users will bid with.
     * @param _hook Address of the hook contract if any.
     * @return _newAuction Address of the newly created auction contract.
     */
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

    /**
     * @notice Creates a new auction contract.
     * @param _want Address of the token users will bid with.
     * @param _hook Address of the hook contract if any.
     * @param _governance Address allowed to enable and disable auctions.
     * @return _newAuction Address of the newly created auction contract.
     */
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

    /**
     * @notice Creates a new auction contract.
     * @param _want Address of the token users will bid with.
     * @param _hook Address of the hook contract if any.
     * @param _governance Address allowed to enable and disable auctions.
     * @param _auctionLength Length of the auction in seconds.
     * @return _newAuction Address of the newly created auction contract.
     */
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

    /**
     * @notice Creates a new auction contract.
     * @param _want Address of the token users will bid with.
     * @param _hook Address of the hook contract if any.
     * @param _governance Address allowed to enable and disable auctions.
     * @param _auctionLength Length of the auction in seconds.
     * @param _auctionCooldown Minimum time period between kicks in seconds.
     * @return _newAuction Address of the newly created auction contract.
     */
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

    /**
     * @notice Creates a new auction contract.
     * @param _want Address of the token users will bid with.
     * @param _hook Address of the hook contract if any.
     * @param _governance Address allowed to enable and disable auctions.
     * @param _auctionLength Length of the auction in seconds.
     * @param _auctionCooldown Minimum time period between kicks in seconds.
     * @param _startingPrice Starting price for the auction (no decimals).
     * @return _newAuction Address of the newly created auction contract.
     */
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

    /**
     * @dev Deploys and initializes a new Auction
     */
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

        emit DeployedNewAuction(_newAuction, _want);
    }
}
