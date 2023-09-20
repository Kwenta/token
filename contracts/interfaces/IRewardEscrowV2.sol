// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface IRewardEscrowV2 {
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/

    /// @notice A vesting entry contains the data for each escrow NFT
    struct VestingEntry {
        // The amount of KWENTA stored in this vesting entry
        uint256 escrowAmount;
        // The length of time until the entry is fully matured
        uint256 duration;
        // The time at which the entry will be fully matured
        uint256 endTime;
        // The percentage fee for vesting immediately
        // The actual penalty decreases linearly with time until it reaches 0 at block.timestamp=endTime
        uint256 earlyVestingFee;
    }

    /// @notice The same as VestingEntry but packed to fit in a single slot
    struct VestingEntryPacked {
        uint144 escrowAmount;
        uint40 duration;
        uint64 endTime;
        uint8 earlyVestingFee;
    }

    /// @notice Helper struct for getVestingSchedules view
    struct VestingEntryWithID {
        // The amount of KWENTA stored in this vesting entry
        uint256 escrowAmount;
        // The unique ID of this escrow entry NFT
        uint256 entryID;
        // The time at which the entry will be fully matured
        uint256 endTime;
    }

    /*///////////////////////////////////////////////////////////////
                                INITIALIZER
    ///////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract
    /// @param _owner The address of the owner of this contract
    /// @dev this function should be called via proxy, not via direct contract interaction
    function initialize(address _owner) external;

    /*///////////////////////////////////////////////////////////////
                                SETTERS
    ///////////////////////////////////////////////////////////////*/

    /// @notice Function used to define the StakingRewardsV2 contract address to use
    /// @param _stakingRewards The address of the StakingRewardsV2 contract
    /// @dev This function can only be called once
    function setStakingRewards(address _stakingRewards) external;

    /// @notice Function used to define the EscrowMigrator contract address to use
    /// @param _escrowMigrator The address of the EscrowMigrator contract
    function setEscrowMigrator(address _escrowMigrator) external;

    /// @notice Function used to define the TreasuryDAO address to use
    /// @param _treasuryDAO The address of the TreasuryDAO
    /// @dev This function can only be called multiple times
    function setTreasuryDAO(address _treasuryDAO) external;

    /*///////////////////////////////////////////////////////////////
                                VIEWS
    ///////////////////////////////////////////////////////////////*/

    /// @notice Minimum early vesting fee
    /// @dev this must be high enought to prevent governance attacks where the user
    /// can set the early vesting fee to a very low number, stake, vote, then withdraw
    /// via vesting which avoids the unstaking cooldown
    function MINIMUM_EARLY_VESTING_FEE() external view returns (uint256);

    /// @notice Default early vesting fee
    /// @dev This is the default fee applied for early vesting
    function DEFAULT_EARLY_VESTING_FEE() external view returns (uint256);

    /// @notice Default escrow duration
    /// @dev This is the default duration for escrow
    function DEFAULT_DURATION() external view returns (uint256);

    /// @notice helper function to return kwenta address
    function getKwentaAddress() external view returns (address);

    /// @notice A simple alias to totalEscrowedAccountBalance
    function escrowedBalanceOf(address _account) external view returns (uint256);

    /// @notice Get the amount of escrowed kwenta that is not staked for a given account
    function unstakedEscrowedBalanceOf(address _account) external view returns (uint256);

    /// @notice Get the details of a given vesting entry
    /// @param _entryID The id of the vesting entry.
    /// @return endTime the vesting entry object
    /// @return escrowAmount rate per second emission.
    /// @return duration the duration of the vesting entry.
    /// @return earlyVestingFee the early vesting fee of the vesting entry.
    function getVestingEntry(uint256 _entryID)
        external
        view
        returns (uint256, uint256, uint256, uint256);

    /// @notice Get the vesting entries for a given account
    /// @param _account The account to get the vesting entries for
    /// @param _index The index of the first vesting entry to get
    /// @param _pageSize The number of vesting entries to get
    /// @return vestingEntries the list of vesting entries with ids
    function getVestingSchedules(address _account, uint256 _index, uint256 _pageSize)
        external
        view
        returns (VestingEntryWithID[] memory);

    /// @notice Get the vesting entries for a given account
    /// @param _account The account to get the vesting entries for
    /// @param _index The index of the first vesting entry to get
    /// @param _pageSize The number of vesting entries to get
    /// @return vestingEntries the list of vesting entry ids
    function getAccountVestingEntryIDs(address _account, uint256 _index, uint256 _pageSize)
        external
        view
        returns (uint256[] memory);

    /// @notice Get the amount that can be vested now for a set of vesting entries
    /// @param _entryIDs The ids of the vesting entries to get the quantity for
    /// @return total The total amount that can be vested for these entries
    /// @return totalFee The total amount of fees that will be paid for these vesting entries
    function getVestingQuantity(uint256[] calldata _entryIDs)
        external
        view
        returns (uint256, uint256);

    /// @notice Get the amount that can be vested now for a given vesting entry
    /// @param _entryID The id of the vesting entry to get the quantity for
    /// @return quantity The total amount that can be vested for this entry
    /// @return totalFee The total amount of fees that will be paid for this vesting entry
    function getVestingEntryClaimable(uint256 _entryID) external view returns (uint256, uint256);

    /*///////////////////////////////////////////////////////////////
                            MUTATIVE FUNCTIONS
    ///////////////////////////////////////////////////////////////*/

    /// @notice Vest escrowed amounts that are claimable - allows users to vest their vesting entries based on msg.sender
    /// @param _entryIDs The ids of the vesting entries to vest
    function vest(uint256[] calldata _entryIDs) external;

    /// @notice Utilized by the escrow migrator contract to transfer V1 escrow
    /// @param _account The account to import the escrow entry to
    /// @param entryToImport The vesting entry to import
    function importEscrowEntry(address _account, VestingEntry memory entryToImport) external;

    /// @notice Create an escrow entry to lock KWENTA for a given duration in seconds
    /// @param _beneficiary The account that will be able to withdraw the escrowed amount
    /// @param _deposit The amount of KWENTA to escrow
    /// @param _duration The duration in seconds to lock the KWENTA for
    /// @param _earlyVestingFee The fee to apply if the escrowed amount is withdrawn before the end of the vesting period
    /// @dev the early vesting fee decreases linearly over the vesting period
    /// @dev This call expects that the depositor (msg.sender) has already approved the Reward escrow contract
    /// to spend the the amount being escrowed.
    function createEscrowEntry(
        address _beneficiary,
        uint256 _deposit,
        uint256 _duration,
        uint256 _earlyVestingFee
    ) external;

    /// @notice Add a new vesting entry at a given time and quantity to an account's schedule.
    /// @dev A call to this should accompany a previous successful call to kwenta.transfer(rewardEscrow, amount),
    /// to ensure that when the funds are withdrawn, there is enough balance.
    /// This is only callable by the staking rewards contract
    /// The duration defaults to 1 year, and the early vesting fee to 90%
    /// @param _account The account to append a new vesting entry to.
    /// @param _quantity The quantity of KWENTA that will be escrowed.
    function appendVestingEntry(address _account, uint256 _quantity) external;

    /// @notice Transfer multiple entries from one account to another
    ///  Sufficient escrowed KWENTA must be unstaked for the transfer to succeed
    /// @param _from The account to transfer the entries from
    /// @param _to The account to transfer the entries to
    /// @param _entryIDs a list of the ids of the entries to transfer
    function bulkTransferFrom(address _from, address _to, uint256[] calldata _entryIDs) external;

    /// @dev Triggers stopped state
    function pauseRewardEscrow() external;

    /// @dev Returns to normal state.
    function unpauseRewardEscrow() external;

    /*///////////////////////////////////////////////////////////////
                                EVENTS
    ///////////////////////////////////////////////////////////////*/

    /// @notice emitted when an escrow entry is vested
    /// @param beneficiary The account that was vested to
    /// @param value The amount of KWENTA that was vested
    event Vested(address indexed beneficiary, uint256 value);

    /// @notice emitted when an escrow entry is created
    /// @param beneficiary The account that gets the entry
    /// @param value The amount of KWENTA that was escrowed
    /// @param duration The duration in seconds of the vesting entry
    /// @param entryID The id of the vesting entry
    /// @param earlyVestingFee The early vesting fee of the vesting entry
    event VestingEntryCreated(
        address indexed beneficiary,
        uint256 value,
        uint256 duration,
        uint256 entryID,
        uint256 earlyVestingFee
    );

    /// @notice emitted when the staking rewards contract is set
    /// @param stakingRewards The address of the staking rewards contract
    event StakingRewardsSet(address stakingRewards);

    /// @notice emitted when the escrow migrator contract is set
    /// @param escrowMigrator The address of the escrow migrator contract
    event EscrowMigratorSet(address escrowMigrator);

    /// @notice emitted when the treasury DAO is set
    /// @param treasuryDAO The address of the treasury DAO
    event TreasuryDAOSet(address treasuryDAO);

    /// @notice emitted when the early vest fee is sent to the treasury and notifier
    /// @param amountToTreasury The amount of KWENTA sent to the treasury
    /// @param amountToNotifier The amount of KWENTA sent to the notifier
    event EarlyVestFeeSent(uint256 amountToTreasury, uint256 amountToNotifier);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Thrown when attempting to bulk transfer from and to the same address
    error CannotTransferToSelf();

    /// @notice Insufficient unstaked escrow to facilitate transfer
    /// @param escrowAmount the amount of escrow attempted to transfer
    /// @param unstakedBalance the amount of unstaked escrow available
    error InsufficientUnstakedBalance(uint256 escrowAmount, uint256 unstakedBalance);

    /// @notice Attempted to set entry early vesting fee beyond 100%
    error EarlyVestingFeeTooHigh();

    /// @notice cannot mint entries with early vesting fee below the minimum
    error EarlyVestingFeeTooLow();

    /// @notice error someone other than staking rewards calls an onlyStakingRewards function
    error OnlyStakingRewards();

    /// @notice error someone other than escrow migrator calls an onlyEscrowMigrator function
    error OnlyEscrowMigrator();

    /// @notice staking rewards is only allowed to be set once
    error StakingRewardsAlreadySet();

    /// @notice cannot set this value to the zero address
    error ZeroAddress();

    /// @notice cannot mint entries with zero escrow
    error ZeroAmount();

    /// @notice Cannot escrow with 0 duration OR above max_duration
    error InvalidDuration();
}
