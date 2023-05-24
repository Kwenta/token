// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface ITokenDistributor {

    // View Functions

    /// @notice view function for calculating fees for an epoch
    function calculateEpochFees() external view returns(uint256);

    // Mutative Functions

    function checkpointToken() external;

    function claimEpoch(address to, uint epochNumber) external returns (uint256);

    function claimMany(address to, uint[] memory epochs) external;


    
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

}