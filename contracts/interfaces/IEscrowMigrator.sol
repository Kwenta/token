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
        bool confirmed;
        bool migrated;
    }

    enum MigrationStatus {
        NOT_STARTED,
        INITIATED,
        REGISTERED,
        VESTING_CONFIRMED,
        PAID,
        COMPLETED
    }

    // Register start of migration - stores users vested balance
    // Confirm entries - register the escrow entries

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
    function pauseRewardEscrow() external;

    /// @notice Unpause the reward escrow contract
    function unpauseRewardEscrow() external;

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice cannot set this value to the zero address
    error ZeroAddress();

    /// @notice the caller is not approved to take this action
    error NotApproved();

    error MustClaimStakingRewards();

    error MigrationAlreadyStarted();

    error NoEscrowBalanceToMigrate();

    error MustBeInitiatedOrRegistered();

    error MustBeInRegisteredState();

    error MustBeInVestedState();

    error MustBeInPaidState();
}
