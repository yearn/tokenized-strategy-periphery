// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.18;

import {BaseHooks, ERC20} from "../Hooks/BaseHooks.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

abstract contract AsyncRedeem is BaseHooks {
    event RedeemRequested(
        address indexed user,
        uint256 indexed shares,
        uint256 unlockTimestamp
    );
    event WithdrawWindowUpdated(uint256 newWithdrawWindow);
    event WithdrawCooldownUpdated(uint256 newWithdrawCooldown);

    struct RedeemRequest {
        uint256 shares;
        uint256 unlockTimestamp;
    }

    /// @notice The cooldown period after a withdraw request before the user can withdraw.
    uint256 public withdrawCooldown;

    /// @notice The window of time after a withdraw request has cooled down that the withdraw can be processed.
    /// If this window passes without the user calling `withdraw`, the user will need to recall `requestWithdraw`.
    uint256 public withdrawWindow;

    /// @notice The amount of shares that are pending redemption.
    uint256 public pendingRedemptions;

    /// @notice The withdraw requests of users.
    mapping(address => RedeemRequest) public redeemRequests;

    constructor(
        address _asset,
        string memory _name,
        uint256 _withdrawCooldown,
        uint256 _withdrawWindow
    ) BaseHooks(_asset, _name) {
        require(_withdrawCooldown < 365 days, "too long");
        require(_withdrawWindow > 1 days, "too short");

        withdrawCooldown = _withdrawCooldown;
        emit WithdrawCooldownUpdated(_withdrawCooldown);

        withdrawWindow = _withdrawWindow;
        emit WithdrawWindowUpdated(_withdrawWindow);
    }

    function _postWithdrawHook(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) internal virtual override {
        // Fully reset the withdraw request.
        pendingRedemptions -= shares;
        redeemRequests[owner].shares -= shares;
        super._postWithdrawHook(assets, shares, receiver, owner, maxLoss);
    }

    function availableWithdrawLimit(
        address _owner
    ) public view override returns (uint256) {
        RedeemRequest memory request = redeemRequests[_owner];
        if (
            // If the cooldown period has passed
            request.unlockTimestamp < block.timestamp &&
            // And the window has not passed
            request.unlockTimestamp + withdrawWindow > block.timestamp
        ) {
            return
                Math.min(
                    TokenizedStrategy.convertToAssets(request.shares),
                    withdrawLiquidity()
                );
        }
        return 0;
    }

    /**
     * @notice The amount of liquidity that can be withdrawn.
     */
    function withdrawLiquidity() public view virtual returns (uint256);

    /**
     * @notice Requests a redemption of shares from the strategy.
     * @dev This will override any existing redeem request.
     * @param _shares The amount of shares to redeem.
     */
    function requestRedeem(uint256 _shares) external {
        _shares = Math.min(_shares, TokenizedStrategy.balanceOf(msg.sender));

        redeemRequests[msg.sender] = RedeemRequest({
            shares: _shares,
            unlockTimestamp: block.timestamp + withdrawCooldown
        });

        pendingRedemptions += _shares;

        emit RedeemRequested(
            msg.sender,
            _shares,
            block.timestamp + withdrawCooldown
        );
    }

    /**
     * @dev Set the withdraw cooldown.
     * @param _withdrawCooldown The withdraw cooldown.
     */
    function setWithdrawCooldown(
        uint256 _withdrawCooldown
    ) external onlyManagement {
        require(_withdrawCooldown < 365 days, "too long");
        withdrawCooldown = _withdrawCooldown;
        emit WithdrawCooldownUpdated(_withdrawCooldown);
    }

    /**
     * @dev Set the withdraw window.
     * @param _withdrawWindow The withdraw window.
     */
    function setWithdrawWindow(
        uint256 _withdrawWindow
    ) external onlyManagement {
        require(_withdrawWindow > 1 days, "too short");
        withdrawWindow = _withdrawWindow;
        emit WithdrawWindowUpdated(_withdrawWindow);
    }
}
