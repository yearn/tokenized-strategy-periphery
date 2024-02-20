// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.18;

import {Auction} from "./Auction.sol";
import {Clonable} from "../utils/Clonable.sol";

/// @title AuctionFactory
/// @notice Deploy a new Auction.
contract AuctionFactory is Clonable {
    event DeployedNewAuction(address indexed auction, address indexed want);

    /// @notice The time that each auction lasts.
    uint256 public constant DEFAULT_AUCTION_LENGTH = 1 days;

    /// @notice The minimum time to wait between auction 'kicks'.
    uint256 public constant DEFAULT_AUCTION_COOLDOWN = 5 days;

    /// @notice The amount to start the auction with.
    uint256 public constant DEFAULT_STARTING_PRICE = 1_000_000;

    /// @notice Full array of all auctions deployed through this factory.
    address[] public auctions;

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
                DEFAULT_AUCTION_LENGTH,
                DEFAULT_AUCTION_COOLDOWN,
                DEFAULT_STARTING_PRICE
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
                DEFAULT_AUCTION_LENGTH,
                DEFAULT_AUCTION_COOLDOWN,
                DEFAULT_STARTING_PRICE
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
                DEFAULT_AUCTION_LENGTH,
                DEFAULT_AUCTION_COOLDOWN,
                DEFAULT_STARTING_PRICE
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
                DEFAULT_AUCTION_COOLDOWN,
                DEFAULT_STARTING_PRICE
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
                DEFAULT_STARTING_PRICE
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
     *  NOTE: The starting price should be without decimals (1k == 1_000).
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

        auctions.push(_newAuction);

        emit DeployedNewAuction(_newAuction, _want);
    }

    /**
     * @notice Get the full list of auctions deployed through this factory.
     */
    function getAllAuctions() external view returns (address[] memory) {
        return auctions;
    }

    /**
     * @notice Get the total number of auctions deployed through this factory.
     */
    function numberOfAuctions() external view returns (uint256) {
        return auctions.length;
    }
}
