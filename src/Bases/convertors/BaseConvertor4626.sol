// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Auction} from "../../Auctions/AuctionFactory.sol";
import {BaseConvertor} from "./BaseConvertor.sol";

/**
 * @title BaseConvertor4626
 * @dev Convertor extension that deploys `want` into an ERC4626 vault.
 */
contract BaseConvertor4626 is BaseConvertor {
    using SafeERC20 for ERC20;

    IERC4626 public immutable vault;

    constructor(
        address _asset,
        string memory _name,
        address _want,
        address _vault,
        address _oracle
    ) BaseConvertor(_asset, _name, _want, _oracle) {
        vault = IERC4626(_vault);
        require(vault.asset() == _want, "wrong vault");

        want.forceApprove(_vault, type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                            EXTERNAL API
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploy loose `want` into the vault.
    function deployLooseWant() external onlyKeepers returns (uint256) {
        return _deployLooseWant();
    }

    function freeWant(uint256 _wantAmount) external onlyKeepers {
        uint256 freedWant = _freeWantFromVault(_wantAmount);
        if (freedWant > 0) {
            _kickConfiguredAuction(buyAssetAuction, address(want));
        }
    }

    function freeWantFromVault(uint256 _wantAmount) external onlyKeepers {
        _freeWantFromVault(_wantAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                VIEWS
    //////////////////////////////////////////////////////////////*/

    function balanceOfVault() public view virtual returns (uint256) {
        return vault.balanceOf(address(this));
    }

    /// @notice Asset-denominated value of vault holdings.
    function valueOfVault() public view virtual returns (uint256) {
        return _quoteAssetFromWant(_valueOfVaultInWant());
    }

    /// @notice Asset-denominated max withdrawable value from vault.
    function vaultsMaxWithdraw() public view virtual returns (uint256) {
        return
            _quoteAssetFromWant(
                vault.convertToAssets(vault.maxRedeem(address(this)))
            );
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL VIEWS
    //////////////////////////////////////////////////////////////*/

    function _valueOfVaultInWant() internal view virtual returns (uint256) {
        return vault.convertToAssets(balanceOfVault());
    }

    function _deployableWant() internal view virtual returns (uint256) {
        return Math.min(balanceOfWant(), vault.maxDeposit(address(this)));
    }

    /*//////////////////////////////////////////////////////////////
                           STRATEGY HOOKS
    //////////////////////////////////////////////////////////////*/

    function availableDepositLimit(
        address _owner
    ) public view virtual override returns (uint256) {
        uint256 depositLimit = super.availableDepositLimit(_owner);
        if (depositLimit == 0) return 0;

        uint256 maxDepositInWant = vault.maxDeposit(address(this));
        if (maxDepositInWant == type(uint256).max) {
            return depositLimit;
        }

        return Math.min(depositLimit, _quoteAssetFromWant(maxDepositInWant));
    }

    function _claimAndSellRewards() internal virtual override {
        _deployLooseWant();
    }

    function _tend(uint256) internal virtual override {
        _deployLooseWant();
    }

    function _tendTrigger() internal view virtual override returns (bool) {
        return _deployableWant() > minAmountToSell;
    }

    function totalWant() internal view virtual override returns (uint256) {
        return super.totalWant() + _valueOfVaultInWant();
    }

    function _emergencyWithdraw(uint256 _amount) internal virtual override {
        uint256 wantAmount = _quoteWantFromAsset(_amount);
        _freeWantFromVault(wantAmount);
        _kickConfiguredAuction(buyAssetAuction, address(want));
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL ACTIONS
    //////////////////////////////////////////////////////////////*/

    function _deployLooseWant() internal virtual returns (uint256 _deployed) {
        _deployed = _deployableWant();

        if (_deployed != 0) {
            vault.deposit(_deployed, address(this));
        }
    }

    function _freeWantFromVault(
        uint256 _wantAmount
    ) internal virtual returns (uint256) {
        uint256 wantBalance = balanceOfWant();

        if (wantBalance >= _wantAmount) return _wantAmount;

        _wantAmount -= wantBalance;

        uint256 shares = Math.min(
            vault.previewWithdraw(vault.balanceOf(address(this))),
            Math.min(_wantAmount, vault.maxRedeem(address(this)))
        );

        if (shares == 0) return 0;

        return vault.redeem(shares, address(this), address(this));
    }
}
