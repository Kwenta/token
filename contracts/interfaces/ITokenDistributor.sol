// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

interface ITokenDistributor {
    // Events

    /// @notice event for a new checkpoint
    /// @param time: the timestamp of the checkpoint
    /// @param tokens: amount of tokens checkpointed
    event CheckpointToken(uint time, uint tokens);

    /// @notice event for a epoch that gets claimed
    /// @param user: who claimed the epoch
    /// @param epoch: the epoch number that was claimed
    /// @param tokens: the amount of tokens claimed
    event EpochClaim(address user, uint epoch, uint tokens);

    // Errors

    /// @notice error when constructor addresses are 0
    error ZeroAddress();

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

    /// @notice error when user tries to claim 0 fees
    error CannotClaim0Fees();

    // View Functions

    /// @notice mapping for tokens allocated to each epoch
    /// @param epochNumber: the epoch number
    /// @return tokens for that epoch
    function tokensPerEpoch(uint epochNumber) external view returns (uint);

    /// @notice view function for calculating fees for an epoch
    /// based off staked balances from StakingRewardsV2
    /// @param to: the address the fees are being calculated for
    /// @param epochNumber: the epoch the fees are calculated for
    /// @return proportional amount of fees
    function calculateEpochFees(
        address to,
        uint epochNumber
    ) external view returns (uint256);

    // Mutative Functions

    /// @notice checkpointing system for determining tokens per epoch
    function checkpointToken() external;

    /// @notice claim tokens for a certain epoch
    /// @param to: address that epoch is being claimed for
    /// @param epochNumber: epoch that is being claimed
    function claimEpoch(address to, uint epochNumber) external;

    /// @notice claim tokens for many epochs at once
    /// @param to: address that epoch is being claimed for
    /// @param epochs: all the epochs being claimed
    function claimMany(address to, uint[] memory epochs) external;
}
