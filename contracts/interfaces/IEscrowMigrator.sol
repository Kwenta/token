// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IEscrowMigrator {
    /*//////////////////////////////////////////////////////////////
                           STRUCTS AND ENUMS
    //////////////////////////////////////////////////////////////*/

    /// @notice A vesting entry contains the data for each escrow entry
    struct VestingEntry {
        // The amount of KWENTA stored in this vesting entry
        uint248 escrowAmount;
        // Whether the entry has been migrated to v2
        bool migrated;
    }

    /// @notice A vesting entry contains the data for each escrow entry
    struct VestingEntryWithID {
        // The entryID associated with this vesting entry
        uint256 entryID;
        // The amount of KWENTA stored in this vesting entry
        uint256 escrowAmount;
        // Whether the entry has been migrated to v2
        bool migrated;
    }

    /*///////////////////////////////////////////////////////////////
                                INITIALIZER
    ///////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract
    /// @param _owner The address of the owner of this contract
    /// @param _treasuryDAO The address of the treasury DAO
    /// @dev this function should be called via proxy, not via direct contract interaction
    function initialize(address _owner, address _treasuryDAO) external;

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    /// @notice Get the total number of registered vesting entries for a given account
    /// @param _account The address of the account to query
    /// @return The number of vesting entries for the given account
    function numberOfRegisteredEntries(address _account) external view returns (uint256);

    /// @notice Get the total number of migrated vesting entries for a given account
    /// @param _account The address of the account to query
    /// @return The number of vesting entries for the given account
    /// @dev WARNING: loop is potentially limitless - could revert with out of gas error if called on-chain
    function numberOfMigratedEntries(address _account) external view returns (uint256);

    /// @notice Get the total escrowed registerd for an account
    /// @param _account The address of the account to query
    /// @return total the total escrow registered for the given account
    /// @dev WARNING: loop is potentially limitless - could revert with out of gas error if called on-chain
    function totalEscrowRegistered(address _account) external view returns (uint256 total);

    /// @notice Get the total escrowed migrated for an account
    /// @param _account The address of the account to query
    /// @return total the total escrow migrated for the given account
    /// @dev WARNING: loop is potentially limitless - could revert with out of gas error if called on-chain
    function totalEscrowMigrated(address _account) external view returns (uint256 total);

    /// @notice the amount a given user needs to pay to migrate all currently vested
    /// registered entries. The user should approve the escrow migrator for at least
    /// this amount before beginning the migration step
    /// @param _account The address of the account to query
    /// @return toPay the amount the user needs to pay to migrate all currently vested
    function toPay(address _account) external view returns (uint256);

    /// @notice Get the vesting entry data for a given account and entry ID
    /// @param _account The address of the account to query
    /// @param _entryID The ID of the entry to query
    function getRegisteredVestingEntry(address _account, uint256 _entryID)
        external
        view
        returns (uint256 escrowAmount, bool migrated);

    /// @notice get a list of vesting entries for a given account
    /// @param _account The address of the account to query
    /// @param _index The _index of the first entry to query
    /// @param _pageSize The number of entries to query
    function getRegisteredVestingSchedules(address _account, uint256 _index, uint256 _pageSize)
        external
        view
        returns (VestingEntryWithID[] memory);

    /// @notice get a list of vesting entry IDs for a given account
    /// @param _account The address of the account to query
    /// @param _index The index of the first entry to query
    /// @param _pageSize The number of entries to query
    function getRegisteredVestingEntryIDs(address _account, uint256 _index, uint256 _pageSize)
        external
        view
        returns (uint256[] memory);

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
    /// @param _entryIDs: The entries to register for migration
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
    /// @param _to: The address to migrate the entries to
    /// @param _entryIDs: The entries to migrate
    function migrateEntries(address _to, uint256[] calldata _entryIDs) external;

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
    /// @param _to: The address to migrate the entries to
    /// @param _entryIDs: The entries to migrate
    function migrateIntegratorEntries(
        address _integrator,
        address _to,
        uint256[] calldata _entryIDs
    ) external;

    /*//////////////////////////////////////////////////////////////
                             FUND RECOVERY
    //////////////////////////////////////////////////////////////*/

    /// @notice Withdraw excess funds from the contract
    /// @param _to The address to send the funds to
    function withdrawFunds(address _to) external;
    

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

    /// @notice the user may not begin the migration process if they have nothing to migrate
    error NoEscrowBalanceToMigrate();

    /// @notice step 2 canont be called until the user has initiated via step 1
    error MustBeInitiated();

    /// @notice a user must complete migrating within the specified time window after initiating
    error DeadlinePassed();
}
