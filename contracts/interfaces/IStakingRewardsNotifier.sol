// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface IStakingRewardsNotifier {
    // Errors

    /// @notice cannot set this value to the zero address
    error ZeroAddress();

    /// @notice OnlySupplySchedule can access this
    error OnlySupplySchedule();

    /// @notice Staking Rewards contract was already set
    error AlreadySet();

    // Mutative Functions

    /// @notice set the StakingRewardsV2 contract
    /// @param _stakingRewardsV2: address of the StakingRewardsV2 contract
    function setStakingRewardsV2(address _stakingRewardsV2) external;

    /// @notice notify the StakingRewardsV2 contract of the reward amount
    /// @param mintedAmount: amount of rewards minted
    function notifyRewardAmount(uint256 mintedAmount) external;
}
