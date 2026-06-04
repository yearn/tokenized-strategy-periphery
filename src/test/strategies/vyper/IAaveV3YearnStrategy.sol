// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.18;

/**
 * @title  IAaveV3YearnStrategy
 * @notice Solidity interface for the Vyper AaveV3YearnStrategy.
 *         Exposes the full IStrategy ABI (IBaseStrategy + ITokenizedStrategy)
 *         plus Aave-specific custom extensions (APR hint, sweep).
 */
interface IAaveV3YearnStrategy {
    // ── Immutables ────────────────────────────────────────────────────────────
    function asset()     external view returns (address);
    function aave_pool() external view returns (address);
    function atoken()    external view returns (address);
    function FACTORY()   external view returns (address);

    // ── ERC-20 ────────────────────────────────────────────────────────────────
    function name()     external view returns (string memory);
    function symbol()   external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply()                              external view returns (uint256);
    function balanceOf(address account)                 external view returns (uint256);
    function allowance(address owner, address spender)  external view returns (uint256);
    function transfer(address to, uint256 amount)                         external returns (bool);
    function transferFrom(address from, address to, uint256 amount)       external returns (bool);
    function approve(address spender, uint256 amount)                     external returns (bool);

    // ── ERC-4626 ──────────────────────────────────────────────────────────────
    function totalAssets()                   external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function maxDeposit(address receiver)    external view returns (uint256);
    function maxMint(address receiver)       external view returns (uint256);
    function maxWithdraw(address owner)      external view returns (uint256);
    function maxRedeem(address owner)        external view returns (uint256);
    function previewDeposit(uint256 assets)  external view returns (uint256);
    function previewMint(uint256 shares)     external view returns (uint256);
    function previewWithdraw(uint256 assets) external view returns (uint256);
    function previewRedeem(uint256 shares)   external view returns (uint256);
    function deposit(uint256 assets, address receiver)                 external returns (uint256);
    function mint(uint256 shares, address receiver)                    external returns (uint256);
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
    function redeem(uint256 shares, address receiver, address owner)   external returns (uint256);

    // ── Yearn views ───────────────────────────────────────────────────────────
    function apiVersion()               external view returns (string memory);
    function tokenizedStrategyAddress() external view returns (address);
    function pricePerShare()            external view returns (uint256);
    function unlockedShares()           external view returns (uint256);
    function availableDepositLimit(address owner) external view returns (uint256);
    function availableWithdrawLimit(address owner) external view returns (uint256);
    function management()               external view returns (address);
    function pending_management()       external view returns (address);
    function keeper()                   external view returns (address);
    function emergency_admin()          external view returns (address);
    function performance_fee()          external view returns (uint16);
    function performance_fee_recipient() external view returns (address);
    function profit_max_unlock_time()   external view returns (uint256);
    function is_shutdown()              external view returns (bool);
    function last_report()              external view returns (uint256);

    // ── Keeper ────────────────────────────────────────────────────────────────
    function report() external returns (uint256 profit, uint256 loss);
    function tend()   external;
    function tendTrigger() external view returns (bool, bytes memory);

    // ── Management setters ────────────────────────────────────────────────────
    function setPendingManagement(address)     external;
    function acceptManagement()                external;
    function setKeeper(address)                external;
    function setEmergencyAdmin(address)        external;
    function setPerformanceFee(uint16)         external;
    function setPerformanceFeeRecipient(address) external;
    function setProfitMaxUnlockTime(uint256)   external;
    function shutdownStrategy()                external;
    function emergencyWithdraw(uint256 amount) external;

    // ── IBaseStrategy callbacks ───────────────────────────────────────────────
    function deployFunds(uint256 amount)      external;
    function freeFunds(uint256 amount)        external;
    function harvestAndReport()               external returns (uint256);
    function shutdownWithdraw(uint256 amount) external;

    // ── Custom extensions ─────────────────────────────────────────────────────
    function apr_bps()                        external view returns (uint256);
    function setAprBps(uint256 new_bps)       external;
    function sweep(address token, address to) external;
}
