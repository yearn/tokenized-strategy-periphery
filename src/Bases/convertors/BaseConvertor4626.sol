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

    /// @notice Deploy loose `want` into the vault.
    function deployLooseWant() external onlyManagement returns (uint256) {
        return _deployLooseWant();
    }

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

    function kickable(
        address _from
    ) public view virtual override returns (uint256) {
        uint256 _kickable = super.kickable(_from);
        if (_from == address(want)) {
            if (
                buyAssetAuction.isActive(_from) &&
                buyAssetAuction.available(_from) > 0
            ) {
                return 0;
            }
            _kickable += vault.convertToAssets(vault.maxRedeem(address(this)));
        }
        return _kickable;
    }

    function _claimAndSellRewards() internal virtual override {
        super._claimAndSellRewards();
        _deployLooseWant();
    }

    function totalWant() internal view virtual override returns (uint256) {
        return super.totalWant() + _valueOfVaultInWant();
    }

    function _kickConfiguredAuction(
        Auction _auction,
        address _from
    ) internal virtual override returns (uint256) {
        if (_from == address(want)) {
            _freeWantFromVault(type(uint256).max);
        }

        return super._kickConfiguredAuction(_auction, _from);
    }

    function _deployLooseWant() internal virtual returns (uint256 _deployed) {
        uint256 loose = balanceOfWant();
        if (loose == 0) return 0;

        uint256 maxDeposit = vault.maxDeposit(address(this));
        if (maxDeposit == 0) return 0;

        _deployed = maxDeposit == type(uint256).max
            ? loose
            : Math.min(loose, maxDeposit);

        if (_deployed != 0) {
            vault.deposit(_deployed, address(this));
        }
    }

    function _freeWantFromVault(
        uint256 _wantAmount
    ) internal virtual returns (uint256 _freedWant) {
        uint256 maxRedeem = vault.maxRedeem(address(this));
        if (maxRedeem == 0) return 0;

        uint256 maxWithdraw = vault.convertToAssets(maxRedeem);
        if (maxWithdraw == 0) return 0;

        uint256 toWithdraw = Math.min(_wantAmount, maxWithdraw);
        if (toWithdraw == 0) return 0;

        uint256 shares = vault.previewWithdraw(toWithdraw);
        shares = Math.min(shares, maxRedeem);

        if (shares == 0) return 0;

        uint256 beforeWant = balanceOfWant();
        vault.redeem(shares, address(this), address(this));
        _freedWant = balanceOfWant() - beforeWant;
    }

    function _valueOfVaultInWant() internal view virtual returns (uint256) {
        return vault.convertToAssets(balanceOfVault());
    }

    function _emergencyWithdraw(uint256 _amount) internal virtual override {
        uint256 wantAmount = _quoteWantFromAsset(_amount);
        _freeWantFromVault(wantAmount);
    }
}
