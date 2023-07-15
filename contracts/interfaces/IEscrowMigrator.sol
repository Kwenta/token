// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IEscrowMigrator {
    /*//////////////////////////////////////////////////////////////
                                 ENUMS
    //////////////////////////////////////////////////////////////*/

    enum MigrationStatus {
        NOT_STARTED,
        IN_PROGRESS,
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
}
