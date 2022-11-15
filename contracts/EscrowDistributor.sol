// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IRewardEscrow.sol";

contract EscrowDistributor {
    /// @notice rewards escrow contract
    IRewardEscrow public immutable rewardEscrow;

    /// @notice kwenta token contract
    IERC20 public immutable kwenta;

    event BatchEscrowed(
        uint256 totalAccounts,
        uint256 totalTokens,
        uint256 durationWeeks
    );

    constructor(address kwentaAddr, address rewardEscrowAddr) {
        kwenta = IERC20(kwentaAddr);
        rewardEscrow = IRewardEscrow(rewardEscrowAddr);
    }

    /**
     * @notice Set escrow amounts in batches.
     * @dev required to approve this contract address to spend senders tokens before calling
     * @param accounts: list of accounts to escrow
     * @param amounts: corresponding list of amounts to escrow
     * @param durationWeeks: number of weeks to escrow
     */
    function distributeEscrowed(
        address[] calldata accounts,
        uint256[] calldata amounts,
        uint256 durationWeeks
    ) external {
        require(
            accounts.length == amounts.length,
            "Number of accounts does not match number of values"
        );

        uint256 length = accounts.length;
        uint256 totalTokens;
        uint256 duration = durationWeeks * 1 weeks;

        do {
            unchecked {
                --length;
            }
            totalTokens += amounts[length];
        } while (length != 0);

        kwenta.transferFrom(msg.sender, address(this), totalTokens);
        kwenta.approve(address(rewardEscrow), totalTokens);

        length = accounts.length;

        do {
            unchecked {
                --length;
            }
            rewardEscrow.createEscrowEntry(
                accounts[length],
                amounts[length],
                duration
            );
        } while (length != 0);

        emit BatchEscrowed({
            totalAccounts: accounts.length,
            totalTokens: totalTokens,
            durationWeeks: duration
        });
    }
}
