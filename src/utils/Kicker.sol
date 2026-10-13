// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {Auction} from "../Auctions/Auction.sol";
import {ITradeFactory} from "../interfaces/TradeFactory/ITradeFactory.sol";
import {ITokenizedStrategy} from "@tokenized-strategy/interfaces/ITokenizedStrategy.sol";
import {ITradeFactorySwapper} from "../swappers/interfaces/ITradeFactorySwapper.sol";

import {Governance} from "../utils/Governance.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Kicker
/// @notice To be set as `tradeFactory` in strategies to migrate to Auction system
contract Kicker is ITradeFactory, Governance {
    using SafeERC20 for ERC20;

    mapping(address => address) public auctions;

    constructor(address _governance) Governance(_governance) {}

    function enable(address, address) external override {}

    function disable(address, address) external override {}

    function setAuction(
        address _strategy,
        address _auction
    ) external onlyGovernance {
        require(Auction(_auction).receiver() == _strategy, "!receiver");
        require(
            Auction(_auction).want() == ITokenizedStrategy(_strategy).asset(),
            "!asset"
        );
        require(
            ITradeFactorySwapper(_strategy).tradeFactory() == address(this),
            "!trade factory"
        );

        auctions[_strategy] = _auction;
    }

    function kick(address _strategy, address _token) external {
        address _auction = auctions[_strategy];
        require(_auction != address(0), "!auction");

        uint256 _balance = ERC20(_token).balanceOf(_strategy);
        if (_balance > 0) {
            ERC20(_token).safeTransferFrom(_strategy, _auction, _balance);
        }

        Auction(_auction).kick(_token);
    }
}
