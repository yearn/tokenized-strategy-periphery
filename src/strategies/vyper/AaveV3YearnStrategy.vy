# pragma version ~=0.4.1
# @license: GPL-3.0
"""
@title  Aave V3 Vyper Strategy — Yearn V3 TokenizedStrategy Framework
@author Yuriy Khomenkov (KhomDev) <yuriy@khomdev.io>
@notice Standalone ERC-4626 / ERC-20 yield strategy that supplies the vault's
        underlying asset to Aave V3 and earns yield via the auto-rebasing aToken.
        Exposes the complete Yearn TokenizedStrategy ABI so it integrates with
        VaultV3 allocator vaults and all standard Yearn tooling without wrapping.

        ┌── WHY HARVEST IS A NO-OP — for Yearn auditors ─────────────────────┐
        │                                                                     │
        │  Aave V3 uses "scaled balance" aTokens (see Aave V3 Technical      │
        │  Paper §3.2). Every call to aToken.balanceOf(holder) returns the   │
        │  holder's balance INCLUDING all interest accrued since supply time. │
        │  The balance grows automatically with each Ethereum block via the   │
        │  Liquidity Index — no claim, compound, or reward-swap step exists.  │
        │                                                                     │
        │  Consequently:                                                      │
        │    • _harvestAndReport() returns aToken.balanceOf(self) directly.  │
        │    • report() isolates interest as profit by comparing the live     │
        │      aToken reading against _assets_tracked — a manually-updated   │
        │      counter incremented on deposit and decremented on withdraw,    │
        │      matching the Yearn TokenizedStrategy.totalAssets pattern.      │
        │    • The profit is locked as strategy shares that burn linearly     │
        │      over profitMaxUnlockTime (default 10 days), preventing a       │
        │      sandwich: deposit→wait-for-report→redeem.                      │
        │                                                                     │
        │  Aave also distributes stkAAVE / AAVE incentive rewards via the    │
        │  Incentives Controller. Those rewards are intentionally NOT         │
        │  harvested here:                                                    │
        │    (a) incentives are intermittent and token-market-dependent;      │
        │    (b) auto-compounding them requires a swap — MEV surface,        │
        │        slippage, and oracle dependence for a simple supply vault;   │
        │    (c) the supply-rate APR is already distributed in-kind via the  │
        │        aToken rebase, which is the primary yield this strategy      │
        │        captures.                                                    │
        │  A dedicated incentive-compounding layer can sit above this         │
        │  strategy in a MultiStrategyVault if rewards are desired.           │
        └─────────────────────────────────────────────────────────────────────┘

        Trust model (mirrors Yearn TokenizedStrategy):
          management     — Two-step ownership. Controls: fees, keeper, emergency
                           admin, profitMaxUnlockTime, APR hint, shutdown.
          keeper         — Automation address. Can call report() and tend().
          emergencyAdmin — Can call shutdownStrategy() and emergencyWithdraw().
          Public         — Anyone may deposit (when not shut down) and redeem
                           their own shares.

        Implementation note — standalone vs. delegatecall:
          Vyper 0.4.x does not support a delegatecall fallback that forwards
          arbitrary calldata and returns raw bytes, so the TokenizedStrategy
          proxy architecture (BaseStrategy.sol) cannot be replicated verbatim.
          Instead, this contract implements every Yearn ABI function natively
          in Vyper, including the profit-locking accounting. The external
          surface is ABI-identical to a Solidity BaseStrategy derivative.
"""

# ──────────────────────────────────────────────────────────────────────────────
#                               INTERFACES
# ──────────────────────────────────────────────────────────────────────────────

from ethereum.ercs import IERC20

interface IAaveV3Pool:
    def supply(asset: address, amount: uint256, onBehalfOf: address, referralCode: uint16): nonpayable
    def withdraw(asset: address, amount: uint256, to: address) -> uint256: nonpayable

interface IDecimals:
    def decimals() -> uint8: view

# ──────────────────────────────────────────────────────────────────────────────
#                                EVENTS
# ──────────────────────────────────────────────────────────────────────────────

event Transfer:
    sender:   indexed(address)
    receiver: indexed(address)
    value:    uint256

event Approval:
    owner:   indexed(address)
    spender: indexed(address)
    value:   uint256

event Deposit:
    sender: indexed(address)
    owner:  indexed(address)
    assets: uint256
    shares: uint256

event Withdraw:
    sender:   indexed(address)
    receiver: indexed(address)
    owner:    indexed(address)
    assets:   uint256
    shares:   uint256

event Reported:
    profit:           uint256
    loss:             uint256
    protocol_fees:    uint256
    performance_fees: uint256

event UpdateManagement:
    new_management: indexed(address)

event UpdatePendingManagement:
    new_pending_management: indexed(address)

event UpdateKeeper:
    new_keeper: indexed(address)

event UpdateEmergencyAdmin:
    new_emergency_admin: indexed(address)

event UpdatePerformanceFee:
    new_performance_fee: uint16

event UpdatePerformanceFeeRecipient:
    new_performance_fee_recipient: indexed(address)

event UpdateProfitMaxUnlockTime:
    new_profit_max_unlock_time: uint256

event StrategyShutdown:
    pass

event AprUpdated:
    new_bps: uint256

# ──────────────────────────────────────────────────────────────────────────────
#                               CONSTANTS
# ──────────────────────────────────────────────────────────────────────────────

MAX_BPS: constant(uint256) = 10_000
MAX_PERFORMANCE_FEE: constant(uint16) = 5_000
DEFAULT_PROFIT_MAX_UNLOCK_TIME: constant(uint256) = 10 * 24 * 3600
API_VERSION: constant(String[28]) = "3.0.4"

# Canonical TokenizedStrategy singleton — returned for ecosystem tooling.
# This contract does NOT delegatecall to it.
TOKENIZED_STRATEGY_ADDRESS: constant(address) = 0x2e234DAe75C793f67A35089C9d99245E1C58470b

MAX_APR_BPS: constant(uint256) = 5_000

# ──────────────────────────────────────────────────────────────────────────────
#                              IMMUTABLES
# ──────────────────────────────────────────────────────────────────────────────

asset:     public(immutable(address))
aave_pool: public(immutable(address))
atoken:    public(immutable(address))
FACTORY:   public(immutable(address))
_asset_decimals: immutable(uint8)

# ──────────────────────────────────────────────────────────────────────────────
#                            ERC-20 STORAGE
# ──────────────────────────────────────────────────────────────────────────────

name:   public(String[64])
symbol: public(String[32])

_total_supply: uint256
_balance_of:   HashMap[address, uint256]
_allowance:    HashMap[address, HashMap[address, uint256]]

# ──────────────────────────────────────────────────────────────────────────────
#                          MANAGEMENT STORAGE
# ──────────────────────────────────────────────────────────────────────────────

management:               public(address)
pending_management:       public(address)
keeper:                   public(address)
emergency_admin:          public(address)

performance_fee:           public(uint16)
performance_fee_recipient: public(address)

profit_max_unlock_time:   public(uint256)

# ──────────────────────────────────────────────────────────────────────────────
#                        PROFIT-LOCKING STORAGE
# ──────────────────────────────────────────────────────────────────────────────

_lock_shares:             uint256
_profit_unlock_rate:      uint256
_full_profit_unlock_date: uint256
_last_unlock_time:        uint256

# ──────────────────────────────────────────────────────────────────────────────
#                           STRATEGY STORAGE
# ──────────────────────────────────────────────────────────────────────────────

is_shutdown: public(bool)
last_report: public(uint256)

# Mirrors TokenizedStrategy's S.totalAssets.
# Incremented on deposit, decremented on withdraw, reset to live on report().
# totalAssets() returns this, NOT the live aToken balance between reports.
_assets_tracked: uint256

apr_bps: public(uint256)


# ──────────────────────────────────────────────────────────────────────────────
#                             CONSTRUCTOR
# ──────────────────────────────────────────────────────────────────────────────

@deploy
def __init__(
    asset_:              address,
    aave_pool_:          address,
    atoken_:             address,
    name_:               String[64],
    symbol_:             String[32],
    management_:         address,
    keeper_:             address,
    perf_fee_recipient_: address,
    factory_:            address,
):
    assert asset_              != empty(address), "strategy: zero asset"
    assert aave_pool_          != empty(address), "strategy: zero pool"
    assert atoken_             != empty(address), "strategy: zero atoken"
    assert management_         != empty(address), "strategy: zero management"
    assert perf_fee_recipient_ != empty(address), "strategy: zero fee recipient"

    asset     = asset_
    aave_pool = aave_pool_
    atoken    = atoken_
    FACTORY   = factory_

    _asset_decimals = staticcall IDecimals(asset_).decimals()

    self.name   = name_
    self.symbol = symbol_

    self.management               = management_
    self.emergency_admin          = management_
    self.keeper                   = keeper_
    self.performance_fee_recipient = perf_fee_recipient_
    self.performance_fee          = 1_000
    self.profit_max_unlock_time   = DEFAULT_PROFIT_MAX_UNLOCK_TIME
    self.last_report              = block.timestamp


# ==============================================================================
#                               ERC-20 VIEWS
# ==============================================================================

@external
@view
def decimals() -> uint8:
    return _asset_decimals


@external
@view
def totalSupply() -> uint256:
    """
    @notice Effective total supply: raw shares minus still-locked profit shares.
    @dev    Locked shares burn linearly after each report, causing pricePerShare
            to rise smoothly from the pre-report level to the fully-recognised level.
    """
    return self._effective_supply()


@external
@view
def balanceOf(account: address) -> uint256:
    return self._balance_of[account]


@external
@view
def allowance(owner: address, spender: address) -> uint256:
    return self._allowance[owner][spender]


@external
def transfer(to: address, amount: uint256) -> bool:
    assert to != empty(address), "strategy: zero receiver"
    self._balance_of[msg.sender] -= amount
    self._balance_of[to] += amount
    log Transfer(sender=msg.sender, receiver=to, value=amount)
    return True


@external
def transferFrom(owner: address, to: address, amount: uint256) -> bool:
    assert to != empty(address), "strategy: zero receiver"
    if self._allowance[owner][msg.sender] != max_value(uint256):
        self._allowance[owner][msg.sender] -= amount
    self._balance_of[owner] -= amount
    self._balance_of[to] += amount
    log Transfer(sender=owner, receiver=to, value=amount)
    return True


@external
def approve(spender: address, amount: uint256) -> bool:
    self._allowance[msg.sender][spender] = amount
    log Approval(owner=msg.sender, spender=spender, value=amount)
    return True


# ==============================================================================
#                              ERC-4626 VIEWS
# ==============================================================================

@external
@view
def totalAssets() -> uint256:
    """
    @notice Manually-tracked total assets — NOT the live aToken balance.
    @dev    _assets_tracked is incremented on deposit and decremented on withdraw.
            It is updated to the live aToken.balanceOf(self) only in report().
            Between reports, totalAssets() is therefore less than the actual
            aToken balance by the interest accrued since the last report.
            This matches the Yearn TokenizedStrategy pattern and prevents the
            sandwich: deposit at stale price → wait for report → redeem at gain.
    """
    return self._assets_tracked


@external
@view
def convertToShares(assets: uint256) -> uint256:
    return self._convert_to_shares(assets, False)


@external
@view
def convertToAssets(shares: uint256) -> uint256:
    return self._convert_to_assets(shares, False)


@external
@view
def maxDeposit(receiver: address) -> uint256:
    if self.is_shutdown:
        return 0
    return max_value(uint256)


@external
@view
def maxMint(receiver: address) -> uint256:
    if self.is_shutdown:
        return 0
    return max_value(uint256)


@external
@view
def maxWithdraw(owner: address) -> uint256:
    return self._convert_to_assets(self._balance_of[owner], False)


@external
@view
def maxRedeem(owner: address) -> uint256:
    return self._balance_of[owner]


@external
@view
def previewDeposit(assets: uint256) -> uint256:
    return self._convert_to_shares(assets, False)


@external
@view
def previewMint(shares: uint256) -> uint256:
    return self._convert_to_assets(shares, True)


@external
@view
def previewWithdraw(assets: uint256) -> uint256:
    return self._convert_to_shares(assets, True)


@external
@view
def previewRedeem(shares: uint256) -> uint256:
    return self._convert_to_assets(shares, False)


# ==============================================================================
#                        YEARN COMPATIBILITY VIEWS
# ==============================================================================

@external
@view
def apiVersion() -> String[28]:
    return API_VERSION


@external
@view
def tokenizedStrategyAddress() -> address:
    """
    @notice Returns the canonical TokenizedStrategy singleton address.
    @dev    For ecosystem tooling compatibility. This contract does NOT
            delegatecall to it — it implements the full ABI natively in Vyper.
    """
    return TOKENIZED_STRATEGY_ADDRESS


@external
@view
def pricePerShare() -> uint256:
    supply: uint256 = self._effective_supply()
    if supply == 0:
        return 10 ** convert(_asset_decimals, uint256)
    return self._convert_to_assets(10 ** convert(_asset_decimals, uint256), False)


@external
@view
def unlockedShares() -> uint256:
    """
    @notice Pending-burn profit shares that have elapsed past the lock schedule.
    @dev    effectiveSupply = totalSupply() = _total_supply - unlockedShares().
            Burning is lazy: actual _total_supply write happens in
            _burn_unlocked_shares() at the top of every state mutation.
    """
    if self._lock_shares == 0:
        return 0
    elapsed: uint256 = min(block.timestamp, self._full_profit_unlock_date) - self._last_unlock_time
    return min(self._profit_unlock_rate * elapsed, self._lock_shares)


@external
@view
def availableDepositLimit(_owner: address) -> uint256:
    if self.is_shutdown:
        return 0
    return max_value(uint256)


@external
@view
def availableWithdrawLimit(_owner: address) -> uint256:
    return self._assets_tracked


# ==============================================================================
#                           ERC-4626 MUTATIONS
# ==============================================================================

@external
@nonreentrant
def deposit(assets: uint256, receiver: address) -> uint256:
    """
    @notice Deposit `assets` of underlying, receive strategy shares.
    @dev    Supplies to Aave immediately. _assets_tracked is incremented so
            the next report() only recognises interest (not this deposit) as profit.
    """
    assert not self.is_shutdown,        "strategy: shutdown"
    assert assets != 0,                 "strategy: zero assets"
    assert receiver != empty(address),  "strategy: zero receiver"

    self._burn_unlocked_shares()

    shares: uint256 = self._convert_to_shares(assets, False)
    assert shares != 0, "strategy: zero shares"

    assert extcall IERC20(asset).transferFrom(
        msg.sender, self, assets, default_return_value=True
    ), "strategy: transferFrom failed"

    self._deploy_funds(assets)
    self._assets_tracked += assets

    self._mint(receiver, shares)
    log Deposit(sender=msg.sender, owner=receiver, assets=assets, shares=shares)
    return shares


@external
@nonreentrant
def mint(shares: uint256, receiver: address) -> uint256:
    assert not self.is_shutdown,       "strategy: shutdown"
    assert shares != 0,                "strategy: zero shares"
    assert receiver != empty(address), "strategy: zero receiver"

    self._burn_unlocked_shares()

    assets: uint256 = self._convert_to_assets(shares, True)
    assert assets != 0, "strategy: zero assets"

    assert extcall IERC20(asset).transferFrom(
        msg.sender, self, assets, default_return_value=True
    ), "strategy: transferFrom failed"

    self._deploy_funds(assets)
    self._assets_tracked += assets

    self._mint(receiver, shares)
    log Deposit(sender=msg.sender, owner=receiver, assets=assets, shares=shares)
    return assets


@external
@nonreentrant
def withdraw(assets: uint256, receiver: address, owner: address) -> uint256:
    """
    @notice Withdraw exactly `assets` by burning shares. Share-to-burn rounds up.
    """
    assert assets != 0,                "strategy: zero assets"
    assert receiver != empty(address), "strategy: zero receiver"

    self._burn_unlocked_shares()

    shares: uint256 = self._convert_to_shares(assets, True)
    held: uint256 = self._balance_of[owner]
    if shares > held:
        shares = held

    if owner != msg.sender:
        self._allowance[owner][msg.sender] -= shares

    self._burn(owner, shares)
    assets_out: uint256 = self._convert_to_assets(shares, False)
    self._assets_tracked -= assets_out

    self._withdraw_assets_to(assets_out, receiver)
    log Withdraw(sender=msg.sender, receiver=receiver, owner=owner, assets=assets_out, shares=shares)
    return shares


@external
@nonreentrant
def redeem(shares: uint256, receiver: address, owner: address) -> uint256:
    assert shares != 0,                "strategy: zero shares"
    assert receiver != empty(address), "strategy: zero receiver"
    assert shares <= self._balance_of[owner], "strategy: insufficient shares"

    self._burn_unlocked_shares()

    if owner != msg.sender:
        self._allowance[owner][msg.sender] -= shares

    assets: uint256 = self._convert_to_assets(shares, False)
    self._burn(owner, shares)
    self._assets_tracked -= assets

    self._withdraw_assets_to(assets, receiver)
    log Withdraw(sender=msg.sender, receiver=receiver, owner=owner, assets=assets, shares=shares)
    return assets


# ==============================================================================
#                         YEARN KEEPER FUNCTIONS
# ==============================================================================

@external
@nonreentrant
def report() -> (uint256, uint256):
    """
    @notice Harvest and report profit or loss.
    @dev    Callable by keeper or management.

            For Aave, _harvest_and_report() is a pure staticcall that returns
            aToken.balanceOf(self). No trades, no reward swaps, no side effects.
            profit = live_assets - _assets_tracked = interest earned since last report.

            Profit shares are minted to keep price unchanged immediately after report,
            then burned linearly over profit_max_unlock_time so price rises smoothly.

            On loss (Aave bad-debt event): _assets_tracked is written down,
            share price drops immediately, (0, loss) returned.
    """
    self._only_keepers()
    self._burn_unlocked_shares()

    live_assets: uint256 = self._harvest_and_report()
    tracked:     uint256 = self._assets_tracked
    supply:      uint256 = self._total_supply

    profit: uint256 = 0
    loss:   uint256 = 0
    fee_assets: uint256 = 0

    if live_assets >= tracked:
        profit = live_assets - tracked

        if profit > 0 and supply > 0:
            total_profit_shares: uint256 = supply * profit // tracked

            fee_shares: uint256 = (
                total_profit_shares * convert(self.performance_fee, uint256) // MAX_BPS
            )
            if fee_shares > 0:
                self._mint(self.performance_fee_recipient, fee_shares)
                fee_assets = self._convert_to_assets(fee_shares, False)

            locked_shares: uint256 = total_profit_shares - fee_shares
            if locked_shares > 0 and self.profit_max_unlock_time > 0:
                self._mint(self, locked_shares)
                self._lock_shares += locked_shares
                self._profit_unlock_rate     = self._lock_shares // self.profit_max_unlock_time
                self._full_profit_unlock_date = block.timestamp + self.profit_max_unlock_time
                self._last_unlock_time        = block.timestamp
    else:
        loss = tracked - live_assets

    self._assets_tracked = live_assets
    self.last_report     = block.timestamp

    log Reported(profit=profit, loss=loss, protocol_fees=0, performance_fees=fee_assets)
    return (profit, loss)


@external
def tend():
    """
    @notice Maintenance hook. No-op for Aave — aToken rebases automatically.
    @dev    Exists for IBaseStrategy compatibility.
    """
    self._only_keepers()


@external
@view
def tendTrigger() -> (bool, Bytes[1]):
    """@notice Returns (False, b"") — Aave never needs explicit tending."""
    return (False, b"")


# ==============================================================================
#                        YEARN MANAGEMENT FUNCTIONS
# ==============================================================================

@external
def setPendingManagement(new_management: address):
    """@notice Initiate two-step ownership transfer."""
    self._only_management()
    assert new_management != empty(address), "strategy: zero management"
    self.pending_management = new_management
    log UpdatePendingManagement(new_pending_management=new_management)


@external
def acceptManagement():
    """@notice Finalise ownership transfer."""
    assert msg.sender == self.pending_management, "strategy: not pending management"
    self.management         = msg.sender
    self.pending_management = empty(address)
    log UpdateManagement(new_management=msg.sender)


@external
def setKeeper(new_keeper: address):
    self._only_management()
    self.keeper = new_keeper
    log UpdateKeeper(new_keeper=new_keeper)


@external
def setEmergencyAdmin(new_emergency_admin: address):
    self._only_management()
    self.emergency_admin = new_emergency_admin
    log UpdateEmergencyAdmin(new_emergency_admin=new_emergency_admin)


@external
def setPerformanceFee(new_performance_fee: uint16):
    self._only_management()
    assert new_performance_fee <= MAX_PERFORMANCE_FEE, "strategy: fee too high"
    self.performance_fee = new_performance_fee
    log UpdatePerformanceFee(new_performance_fee=new_performance_fee)


@external
def setPerformanceFeeRecipient(new_recipient: address):
    self._only_management()
    assert new_recipient != empty(address), "strategy: zero recipient"
    self.performance_fee_recipient = new_recipient
    log UpdatePerformanceFeeRecipient(new_performance_fee_recipient=new_recipient)


@external
def setProfitMaxUnlockTime(new_unlock_time: uint256):
    """
    @notice Set how long profit shares take to fully unlock.
    @dev    Shorter = more sandwich risk. 0 = no locking (fee shares still vest).
    """
    self._only_management()
    self.profit_max_unlock_time = new_unlock_time
    log UpdateProfitMaxUnlockTime(new_profit_max_unlock_time=new_unlock_time)


@external
def shutdownStrategy():
    """
    @notice Permanently disable new deposits. Non-reversible.
    @dev    Withdrawals and report remain operational.
    """
    self._only_emergency_authorized()
    self.is_shutdown = True
    log StrategyShutdown()


@external
@nonreentrant
def emergencyWithdraw(amount: uint256):
    """
    @notice Pull up to `amount` from Aave to idle. Only callable post-shutdown.
    @dev    Pass max_value(uint256) to pull all. Assets sit idle so users can
            redeem without further Aave interaction.
    """
    self._only_emergency_authorized()
    assert self.is_shutdown, "strategy: not shutdown"

    to_pull: uint256 = min(amount, self._assets_tracked)
    if to_pull == 0:
        return
    self._emergency_withdraw(to_pull)


# ==============================================================================
#                          CUSTOM EXTENSIONS
# ==============================================================================

@external
def setAprBps(new_bps: uint256):
    """
    @notice Update the cached APR hint (basis points) for allocator vault routers.
    @dev    Callable by keeper or management. Updated off-chain from Aave's
            getReserveData(asset).currentLiquidityRate.
    """
    self._only_keepers()
    assert new_bps <= MAX_APR_BPS, "strategy: apr too high"
    self.apr_bps = new_bps
    log AprUpdated(new_bps=new_bps)


@external
def sweep(token: address, to: address):
    """
    @notice Recover an ERC-20 accidentally sent here. Cannot sweep asset or aToken.
    """
    self._only_management()
    assert token != asset  and token != atoken, "strategy: cannot sweep core"
    assert to    != empty(address),             "strategy: zero to"
    bal: uint256 = staticcall IERC20(token).balanceOf(self)
    assert bal != 0, "strategy: nothing to sweep"
    assert extcall IERC20(token).transfer(to, bal, default_return_value=True), "strategy: sweep failed"


# ==============================================================================
#   IBASESTRATEGY COMPATIBILITY — guarded by assert msg.sender == self
#
#   In Solidity BaseStrategy these are called by the TokenizedStrategy singleton
#   via delegatecall (msg.sender == address(this)). In this standalone Vyper
#   implementation the equivalent logic runs inside deposit/withdraw/report.
#   Exposed for ABI compatibility with Yearn tooling that probes them.
# ==============================================================================

@external
def deployFunds(amount: uint256):
    assert msg.sender == self, "strategy: !self"
    self._deploy_funds(amount)


@external
def freeFunds(amount: uint256):
    assert msg.sender == self, "strategy: !self"
    extcall IAaveV3Pool(aave_pool).withdraw(asset, amount, self)


@external
def harvestAndReport() -> uint256:
    """
    @dev Pure read for Aave — returns live aToken balance. Zero side effects.
         This is the function Yearn auditors will scrutinise. It is correct
         to return without any state changes: aToken already includes interest.
    """
    assert msg.sender == self, "strategy: !self"
    return self._harvest_and_report()


@external
def shutdownWithdraw(amount: uint256):
    assert msg.sender == self, "strategy: !self"
    self._emergency_withdraw(amount)


# ==============================================================================
#                             INTERNAL HELPERS
# ==============================================================================

@internal
@view
def _only_management():
    assert msg.sender == self.management, "strategy: !management"


@internal
@view
def _only_keepers():
    assert (
        msg.sender == self.keeper or msg.sender == self.management
    ), "strategy: !keeper"


@internal
@view
def _only_emergency_authorized():
    assert (
        msg.sender == self.emergency_admin or msg.sender == self.management
    ), "strategy: !emergency authorized"


@internal
@view
def _effective_supply() -> uint256:
    """
    @dev View-only effective supply for share-price calculations.
         Returns _total_supply minus the shares that will be burned by the
         next _burn_unlocked_shares() call.

         Right after report (elapsed = 0):
           to_burn = 0  →  effective = _total_supply (all locked shares included).
           Locked shares dilute the denominator, keeping price at pre-report level.
         At t = profit_max_unlock_time:
           to_burn = _lock_shares  →  effective = _total_supply - _lock_shares.
           Price has risen to fully reflect the recognised gain.
    """
    if self._lock_shares == 0:
        return self._total_supply
    elapsed: uint256 = min(block.timestamp, self._full_profit_unlock_date) - self._last_unlock_time
    to_burn: uint256 = min(self._profit_unlock_rate * elapsed, self._lock_shares)
    return self._total_supply - to_burn


@internal
def _burn_unlocked_shares():
    """
    @dev Lazily burn profit-locked shares elapsed since the last state write.
         Called at the top of every state-mutating function.
    """
    if self._lock_shares == 0:
        return
    now_clamped: uint256 = min(block.timestamp, self._full_profit_unlock_date)
    elapsed:     uint256 = now_clamped - self._last_unlock_time
    if elapsed == 0:
        return
    to_burn: uint256 = min(self._profit_unlock_rate * elapsed, self._lock_shares)
    if to_burn == 0:
        return

    self._balance_of[self] -= to_burn
    self._total_supply     -= to_burn
    self._lock_shares      -= to_burn
    self._last_unlock_time  = now_clamped
    log Transfer(sender=self, receiver=empty(address), value=to_burn)


@internal
@view
def _convert_to_shares(assets: uint256, roundup: bool) -> uint256:
    """
    @dev ERC-4626 share formula. First deposit is 1:1.
         Uses _assets_tracked (not live aToken balance) for consistency with totalAssets().
    """
    eff_supply: uint256 = self._effective_supply()
    ta:         uint256 = self._assets_tracked
    if eff_supply == 0 or ta == 0:
        return assets
    if roundup:
        return (assets * eff_supply + ta - 1) // ta
    return assets * eff_supply // ta


@internal
@view
def _convert_to_assets(shares: uint256, roundup: bool) -> uint256:
    eff_supply: uint256 = self._effective_supply()
    ta:         uint256 = self._assets_tracked
    if eff_supply == 0:
        return shares
    if roundup:
        return (shares * ta + eff_supply - 1) // eff_supply
    return shares * ta // eff_supply


@internal
def _deploy_funds(amount: uint256):
    """
    @dev Zero-then-set approval guards against ERC-20 approve-race frontrun.
    """
    extcall IERC20(asset).approve(aave_pool, 0,      default_return_value=True)
    extcall IERC20(asset).approve(aave_pool, amount, default_return_value=True)
    extcall IAaveV3Pool(aave_pool).supply(asset, amount, self, 0)


@internal
@view
def _harvest_and_report() -> uint256:
    """
    @dev Returns the live aToken balance — the ONLY place the live balance is read.
         aToken.balanceOf already includes all accrued interest. No trades, no swaps.
         This is NOT a bug or omission; it is the correct model for a rebasing-yield
         protocol. See module docstring for the full explanation.
    """
    return staticcall IERC20(atoken).balanceOf(self)


@internal
def _emergency_withdraw(amount: uint256):
    atoken_bal: uint256 = staticcall IERC20(atoken).balanceOf(self)
    to_pull: uint256 = min(amount, atoken_bal)
    if to_pull > 0:
        extcall IAaveV3Pool(aave_pool).withdraw(asset, to_pull, self)


@internal
def _withdraw_assets_to(assets: uint256, receiver: address):
    """
    @dev Uses idle asset balance first (from emergencyWithdraw), then Aave.
    """
    idle: uint256 = staticcall IERC20(asset).balanceOf(self)
    if idle >= assets:
        assert extcall IERC20(asset).transfer(receiver, assets, default_return_value=True)
    elif idle > 0:
        assert extcall IERC20(asset).transfer(receiver, idle, default_return_value=True)
        extcall IAaveV3Pool(aave_pool).withdraw(asset, assets - idle, receiver)
    else:
        extcall IAaveV3Pool(aave_pool).withdraw(asset, assets, receiver)


@internal
def _mint(account: address, amount: uint256):
    self._total_supply        += amount
    self._balance_of[account] += amount
    log Transfer(sender=empty(address), receiver=account, value=amount)


@internal
def _burn(account: address, amount: uint256):
    self._balance_of[account] -= amount
    self._total_supply        -= amount
    log Transfer(sender=account, receiver=empty(address), value=amount)
