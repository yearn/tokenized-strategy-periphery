// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Auction} from "./Auction.sol";
import {ClonableCreate2} from "../utils/ClonableCreate2.sol";

/// @title AuctionFactory (Curious Cow Edition)
/// @notice Deploy a new Auction with the ability to let Cowswap settle at the next price.
contract AuctionFactory is ClonableCreate2 {
    event DeployedNewAuction(address indexed auction, address indexed want);

    /// @notice The amount to start the auction with.
    uint256 public constant DEFAULT_STARTING_PRICE = 1_000_000;

    /// @notice Full array of all auctions deployed through this factory.
    address[] public auctions;

    constructor() {
        // Deploy the original
        original = address(new Auction());
    }

    function version() external pure returns (string memory) {
        return "1.0.3cc";
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
                msg.sender,
                msg.sender,
                DEFAULT_STARTING_PRICE,
                bytes32(0)
            );
    }

    /**
     * @notice Creates a new auction contract.
     * @param _want Address of the token users will bid with.
     * @param _receiver Address that will receive the funds in the auction.
     * @return _newAuction Address of the newly created auction contract.
     */
    function createNewAuction(
        address _want,
        address _receiver
    ) external returns (address) {
        return
            _createNewAuction(
                _want,
                _receiver,
                msg.sender,
                DEFAULT_STARTING_PRICE,
                bytes32(0)
            );
    }

    /**
     * @notice Creates a new auction contract.
     * @param _want Address of the token users will bid with.
     * @param _receiver Address that will receive the funds in the auction.
     * @param _governance Address allowed to enable and disable auctions.
     * @return _newAuction Address of the newly created auction contract.
     */
    function createNewAuction(
        address _want,
        address _receiver,
        address _governance
    ) external returns (address) {
        return
            _createNewAuction(
                _want,
                _receiver,
                _governance,
                DEFAULT_STARTING_PRICE,
                bytes32(0)
            );
    }

    /**
     * @notice Creates a new auction contract.
     * @param _want Address of the token users will bid with.
     * @param _receiver Address that will receive the funds in the auction.
     * @param _governance Address allowed to enable and disable auctions.
     * @param _startingPrice Starting price for the auction (no decimals).
     *  NOTE: The starting price should be without decimals (1k == 1_000).
     * @return _newAuction Address of the newly created auction contract.
     */
    function createNewAuction(
        address _want,
        address _receiver,
        address _governance,
        uint256 _startingPrice
    ) external returns (address) {
        return
            _createNewAuction(
                _want,
                _receiver,
                _governance,
                _startingPrice,
                bytes32(0)
            );
    }

    /**
     * @notice Creates a new auction contract.
     * @param _want Address of the token users will bid with.
     * @param _receiver Address that will receive the funds in the auction.
     * @param _governance Address allowed to enable and disable auctions.
     * @param _startingPrice Starting price for the auction (no decimals).
     * @param _salt The salt to use for deterministic deployment.
     * @return _newAuction Address of the newly created auction contract.
     */
    function createNewAuction(
        address _want,
        address _receiver,
        address _governance,
        uint256 _startingPrice,
        bytes32 _salt
    ) external returns (address) {
        return
            _createNewAuction(
                _want,
                _receiver,
                _governance,
                _startingPrice,
                _salt
            );
    }

    /**
     * @dev Deploys and initializes a new Auction
     */
    function _createNewAuction(
        address _want,
        address _receiver,
        address _governance,
        uint256 _startingPrice,
        bytes32 _salt
    ) internal returns (address _newAuction) {
        if (_salt == bytes32(0)) {
            // If none set, generate unique salt. msg.sender gets encoded in getSalt()
            _salt = keccak256(abi.encodePacked(_want, _receiver, _governance));
        }

        _newAuction = _cloneCreate2(_salt);

        Auction(_newAuction).initialize(
            _want,
            _receiver,
            _governance,
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
