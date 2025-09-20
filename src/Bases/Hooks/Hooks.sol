// SPDX-License-Identifier: AGPL-3.0
pragma solidity >=0.8.18;

contract DepositHooks {
    function _preDepositHook(
        uint256 assets,
        uint256 shares,
        address receiver
    ) internal virtual {}

    function _postDepositHook(
        uint256 assets,
        uint256 shares,
        address receiver
    ) internal virtual {}
}

contract WithdrawHooks {
    function _preWithdrawHook(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) internal virtual {}

    function _postWithdrawHook(
        uint256 assets,
        uint256 shares,
        address receiver,
        address owner,
        uint256 maxLoss
    ) internal virtual {}
}

contract TransferHooks {
    function _preTransferHook(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function _postTransferHook(
        address from,
        address to,
        uint256 amount,
        bool success
    ) internal virtual {}
}

contract ReportHooks {
    function _preReportHook() internal virtual {}

    function _postReportHook(uint256 profit, uint256 loss) internal virtual {}
}

contract Hooks is DepositHooks, WithdrawHooks, TransferHooks, ReportHooks {}
