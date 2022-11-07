// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "./interfaces/IRewardEscrow.sol";

contract EscrowDistributor {
    /// @notice kwenta token contract
    address public immutable kwentaAddr;

    /// @notice rewards escrow contract
    address public immutable rewardEscrowAddr;

    event BatchEscrowed(
        uint256 totalAccounts,
        uint256 totalTokens,
        uint256 durationWeeks
    );

    constructor(address _kwentaAddr, address _rewardEscrowAddr) {
        kwentaAddr = _kwentaAddr;
        rewardEscrowAddr = _rewardEscrowAddr;
    }

    /**
     * @notice Set escrow amounts in batches.
     * @dev required to approve this contract address to spend senders tokens before calling
     * @param accounts: list of accounts to escrow
     * @param amounts: corresponding list of amounts to escrow
     * @param durationWeeks: number of weeks to escrow
     */
    function distirbuteEscrowed(
        address[] calldata accounts,
        uint256[] calldata amounts,
        uint256 durationWeeks
    ) external {
        require(
            accounts.length == amounts.length,
            "Number of accounts does not match number of values"
        );

        uint256 totalTokens = 0;
        uint256 duration = durationWeeks * 1 weeks;

        for (uint16 index = 0; index < accounts.length; index++) {
            totalTokens += amounts[index];
        }
        IERC20 kwenta = IERC20(kwentaAddr);
        kwenta.transferFrom(msg.sender, address(this), totalTokens);
        kwenta.approve(rewardEscrowAddr, totalTokens);

        for (uint16 index = 0; index < accounts.length; index++) {
            IRewardEscrow(rewardEscrowAddr).createEscrowEntry(
                accounts[index],
                amounts[index],
                duration
            );
        }

        emit BatchEscrowed(totalTokens, accounts.length, durationWeeks);
    }
}
