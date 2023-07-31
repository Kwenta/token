// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IEscrowMigrator {
    /*//////////////////////////////////////////////////////////////
                           STRUCTS AND ENUMS
    //////////////////////////////////////////////////////////////*/

    /// @notice A vesting entry contains the data for each escrow NFT
    struct VestingEntry {
        // The amount of KWENTA stored in this vesting entry
        uint256 escrowAmount;
        // The length of time until the entry is fully matured
        uint256 duration;
        // The time at which the entry will be fully matured
        uint64 endTime;
        bool migrated;
    }

    /*///////////////////////////////////////////////////////////////
                                INITIALIZER
    ///////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract
    /// @param _owner The address of the owner of this contract
    /// @dev this function should be called via proxy, not via direct contract interaction
    function initialize(address _owner) external;

    /*///////////////////////////////////////////////////////////////
                                PAUSABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Pause the reward escrow contract
    function pauseEscrowMigrator() external;

    /// @notice Unpause the reward escrow contract
    function unpauseEscrowMigrator() external;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice cannot set this value to the zero address
    error ZeroAddress();

    /// @notice the caller is not approved to take this action
    error NotApproved();

    /// @notice users cannot begin the migration process until they have claimed
    /// their last v1 staking rewards
    error MustClaimStakingRewards();

    /// @notice the user may not begin the migration process if they have nothing to migrate
    error NoEscrowBalanceToMigrate();

    /// @notice step 2 canont be called until the user has initiated via step 1
    error MustBeInitiated();
}
