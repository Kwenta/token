// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITokenDistributor {
    // Events

    /// @notice event for a new checkpoint
    event CheckpointToken(uint time, uint tokens);

    /// @notice event for a epoch that gets claimed
    event EpochClaim(address user, uint epoch, uint tokens);

    // Errors

    /// @notice error when offset is more than 7 days
    error OffsetTooBig();

    /// @notice error when user tries to create a new distribution too soon
    error LastEpochHasntEnded();

    /// @notice error when user tries to claim a distribution too soon
    error CannotClaimYet();

    /// @notice error when user tries to claim in new distribution block
    error CannotClaimInNewEpochBlock();

    /// @notice error when user tries to claim for same epoch twice
    error CannotClaimTwice();

    /// @notice error when user tries to claim for epoch with 0 staking
    error NothingStakedThatEpoch();

    /// @notice error when user tries to claim 0 fees
    error CannotClaim0Fees();

    // View Functions

    /// @notice view function for calculating fees for an epoch
    /// based off staked balances from StakingRewardsV2
    function calculateEpochFees(
        address to,
        uint epochNumber
    ) external view returns (uint256);

    // Mutative Functions

    /// @notice checkpointing system for determining tokens per epoch
    function checkpointToken() external;

    /// @notice claim tokens for a certain epoch
    function claimEpoch(address to, uint epochNumber) external;

    /// @notice claim tokens for many epochs at once
    function claimMany(address to, uint[] memory epochs) external;
}
