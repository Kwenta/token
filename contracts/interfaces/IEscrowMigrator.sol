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

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the total number of registered vesting entries for a given account
    /// @param account The address of the account to query
    /// @return The number of vesting entries for the given account
    function numberOfRegisteredEntries(address account) external view returns (uint256);

    /// @notice Get the total number of migrated vesting entries for a given account
    /// @param account The address of the account to query
    /// @return The number of vesting entries for the given account
    function numberOfMigratedEntries(address account) external view returns (uint256);

    /// @notice Get the total escrowed registerd for an account
    /// @param account The address of the account to query
    /// @return total the total escrow registered for the given account
    function totalEscrowRegistered(address account) external view returns (uint256 total);

    /// @notice Get the total escrowed migrated for an account
    /// @param account The address of the account to query
    /// @return total the total escrow migrated for the given account
    function totalEscrowMigrated(address account) external view returns (uint256 total);

    /// @notice the amount a given user needs to pay to migrate all currently vested
    /// registered entries. The user should approve the escrow migrator for at least
    /// this amount before beginning the migration step
    /// @param account The address of the account to query
    /// @return toPay the amount the user needs to pay to migrate all currently vested
    function toPay(address account) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                 STEP 0
    //////////////////////////////////////////////////////////////*/

    /// @notice claim any remaining StakingRewards V1 rewards
    /// This must be done before the migration process can begin

    /*//////////////////////////////////////////////////////////////
                                 STEP 1
    //////////////////////////////////////////////////////////////*/

    /// @notice Step 1 in the migration process - register any entries to be migrated
    /// @param _entryIDs: The entries to register for migration
    /// @dev WARNING: If the user vests non-registerd entries after this step, they will have to pay extra for the migration.
    /// The user should register all entries they want to migrate BEFORE vesting, otherwise it will not be possible to migrate them.
    /// @dev WARNING: To reiterate, if the user vests any entries that are not registered after initiating, they will have
    /// to pay extra for the migration. This is because the user will have to pay for the migration based on the total vested balance at the time of
    /// migration - but only registered entries will be created for them on V2
    function registerEntries(uint256[] calldata _entryIDs) external;

    /*//////////////////////////////////////////////////////////////
                                 STEP 2
    //////////////////////////////////////////////////////////////*/

    /// @notice Vest any registered entries and approve the EscrowMigrator contract
    /// to spend liquid at least the `toPay` amount of $KWENTA
    /// @notice WARNING: DO NOT VEST ANY NON-REGISTERED ENTRIES

    /*//////////////////////////////////////////////////////////////
                                 STEP 3
    //////////////////////////////////////////////////////////////*/

    /// @notice Step 3 in the migration process - migrate the registered entries
    /// @notice The user MUST vest any registered entries before they can be migrated
    /// @notice The user MUST NOT vest any non-registered entries before this step
    function migrateEntries(address to, uint256[] calldata _entryIDs) external;

    /*//////////////////////////////////////////////////////////////
                          INTEGRATOR MIGRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice step 0 - claim any remaining StakingRewards V1 rewards

    /// @notice step 1 - initiate & register entries for migration
    /// @param _integrator: The address of the integrator to register entries for
    /// @param _entryIDs: The entries to register for migration
    /// @dev WARNING: If the integrator vests non-registerd entries after this step, they will have to pay extra for the migration.
    function registerIntegratorEntries(address _integrator, uint256[] calldata _entryIDs)
        external;

    /// @notice step 2 - vest all registered entries and approve the EscrowMigrator contract

    /// @notice step 3 - migrate all registered & vested entries
    /// @param _integrator: The address of the integrator to migrate entries for
    /// @param to: The address to migrate the entries to
    /// @param _entryIDs: The entries to migrate
    function migrateIntegratorEntries(address _integrator, address to, uint256[] calldata _entryIDs)
        external;

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
