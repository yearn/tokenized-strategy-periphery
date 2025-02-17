// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {Hooks} from "./Hooks.sol";
import {BaseHealthCheck, ERC20} from "../HealthCheck/BaseHealthCheck.sol";

/**
 *   @title Base Hooks
 *   @author Yearn.finance
 *   @notice This contract can be inherited by any Yearn
 *   strategy wishing to implement pre or post deposit, withdraw
 *   or transfer hooks in their strategy.
 */
abstract contract BaseHooks is BaseHealthCheck, Hooks {
    constructor(
        address _asset,
        string memory _name
    ) BaseHealthCheck(_asset, _name) {}

    // Deposit
    function deposit(
        uint256 assets,
        address receiver
    ) external virtual returns (uint256 shares) {
        _preDepositHook(assets, shares, receiver);
        shares = abi.decode(
            _delegateCall(
                abi.encodeCall(TokenizedStrategy.deposit, (assets, receiver))
            ),
            (uint256)
        );
        _postDepositHook(assets, shares, receiver);
    }

    // Mint
    function mint(
        uint256 shares,
        address receiver
    ) external virtual returns (uint256 assets) {
        _preDepositHook(assets, shares, receiver);
        assets = abi.decode(
            _delegateCall(
                abi.encodeCall(TokenizedStrategy.mint, (shares, receiver))
            ),
            (uint256)
        );
        _postDepositHook(assets, shares, receiver);
    }

    // Withdraw
    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) external virtual returns (uint256 shares) {
        return withdraw(assets, receiver, owner, 0);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner,
        uint256 maxLoss
    ) public virtual returns (uint256 shares) {
        _preWithdrawHook(assets, shares, receiver, owner, maxLoss);
        shares = abi.decode(
            _delegateCall(
                // Have to use encodeWithSignature due to overloading parameters.
                abi.encodeWithSignature(
                    "withdraw(uint256,address,address,uint256)",
                    assets,
                    receiver,
                    owner,
                    maxLoss
                )
            ),
            (uint256)
        );
        _postWithdrawHook(assets, shares, receiver, owner, maxLoss);
    }

    // Redeem
    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) external virtual returns (uint256) {
        // We default to not limiting a potential loss.
        return redeem(shares, receiver, owner, MAX_BPS);
    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) public returns (uint256 assets) {
        _preWithdrawHook(assets, shares, receiver, owner, maxLoss);
        assets = abi.decode(
            _delegateCall(
                // Have to use encodeWithSignature due to overloading parameters.
                abi.encodeWithSignature(
                    "redeem(uint256,address,address,uint256)",
                    shares,
                    receiver,
                    owner,
                    maxLoss
                )
            ),
            (uint256)
        );
        _postWithdrawHook(assets, shares, receiver, owner, maxLoss);
    }

    // Transfer
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual returns (bool success) {
        _preTransferHook(from, to, amount);
        success = abi.decode(
            _delegateCall(
                abi.encodeCall(
                    TokenizedStrategy.transferFrom,
                    (from, to, amount)
                )
            ),
            (bool)
        );
        _postTransferHook(from, to, amount, success);
    }

    // Transfer from
    function transfer(
        address to,
        uint256 amount
    ) external virtual returns (bool success) {
        _preTransferHook(msg.sender, to, amount);
        success = abi.decode(
            _delegateCall(
                abi.encodeCall(TokenizedStrategy.transfer, (to, amount))
            ),
            (bool)
        );
        _postTransferHook(msg.sender, to, amount, success);
    }

    function report() external virtual returns (uint256 profit, uint256 loss) {
        _preReportHook();
        (profit, loss) = abi.decode(
            _delegateCall(abi.encodeCall(TokenizedStrategy.report, ())),
            (uint256, uint256)
        );
        _postReportHook(profit, loss);
    }
}
