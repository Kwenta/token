// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

library VestingEntries {
    struct VestingEntry {
        uint256 escrowAmount;
        uint256 duration;
        uint64 endTime;
        uint8 earlyVestingFee;
    }

    struct VestingEntryWithID {
        uint256 escrowAmount;
        uint256 entryID;
        uint64 endTime;
    }
}

interface IRewardEscrowV2 {
    /*///////////////////////////////////////////////////////////////
                                INITIALIZER
    ///////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract
    /// @param _owner The address of the owner of this contract
    /// @param _kwenta The address of the Kwenta contract
    /// @dev this function should be called via proxy, not via direct contract interaction
    function initialize(address _owner, address _kwenta) external;

    /*///////////////////////////////////////////////////////////////
                                SETTERS
    ///////////////////////////////////////////////////////////////*/

    /// @notice Function used to define the StakingRewardsV2 contract address to use
    /// @param _stakingRewards The address of the StakingRewardsV2 contract
    /// @dev This function can only be called once
    function setStakingRewards(address _stakingRewards) external;

    /// @notice Function used to define the TreasuryDAO address to use
    /// @param _treasuryDAO The address of the TreasuryDAO
    /// @dev This function can only be called multiple times
    function setTreasuryDAO(address _treasuryDAO) external;

    /*///////////////////////////////////////////////////////////////
                                VIEWS
    ///////////////////////////////////////////////////////////////*/

    /// @notice helper function to return kwenta address
    function getKwentaAddress() external view returns (address);

    /// @notice A simple alias to totalEscrowedAccountBalance
    function totalEscrowedBalanceOf(address _account) external view returns (uint256);

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
        returns (uint64, uint256, uint256, uint8);

    /// @notice Get the vesting entries for a given account
    /// @param _account The account to get the vesting entries for
    /// @param _index The index of the first vesting entry to get
    /// @param _pageSize The number of vesting entries to get
    /// @return vestingEntries the list of vesting entries with ids
    function getVestingSchedules(address _account, uint256 _index, uint256 _pageSize)
        external
        view
        returns (VestingEntries.VestingEntryWithID[] memory);

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
        uint8 _earlyVestingFee
    ) external;

    /// @notice Add a new vesting entry at a given time and quantity to an account's schedule.
    /// @dev A call to this should accompany a previous successful call to kwenta.transfer(rewardEscrow, amount),
    /// to ensure that when the funds are withdrawn, there is enough balance.
    /// This is only callable by the staking rewards contract
    /// @param _account The account to append a new vesting entry to.
    /// @param _quantity The quantity of KWENTA that will be escrowed.
    /// @param _duration The duration that KWENTA will be locked.
    function appendVestingEntry(address _account, uint256 _quantity, uint256 _duration) external;

    /// @notice Stakes escrowed KWENTA.
    /// @dev No tokens are transfered during this process, but the StakingRewards escrowed balance is updated.
    /// @param _amount The amount of escrowed KWENTA to be staked.
    function stakeEscrow(uint256 _amount) external;

    /// @notice Unstakes escrowed KWENTA.
    /// @dev No tokens are transfered during this process, but the StakingRewards escrowed balance is updated.
    /// @param _amount The amount of escrowed KWENTA to be unstaked.
    function unstakeEscrow(uint256 _amount) external;

    /// @notice Transfer multiple tokens from one account to another
    ///  Sufficient escrowed KWENTA must be unstaked for the transfer to succeed
    /// @param _from The account to transfer the tokens from
    /// @param _to The account to transfer the tokens to
    /// @param _entryIDs a list of the ids of the entries to transfer
    function bulkTransferFrom(address _from, address _to, uint256[] calldata _entryIDs) external;

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
    event VestingEntryCreated(
        address indexed beneficiary, uint256 value, uint256 duration, uint256 entryID
    );

    /// @notice emitted the staking rewards contract is set
    /// @param stakingRewardsV2 The address of the staking rewards contract
    event StakingRewardsSet(address stakingRewardsV2);

    /// @notice emitted when the treasury DAO is set
    /// @param treasuryDAO The address of the treasury DAO
    event TreasuryDAOSet(address treasuryDAO);

    /*//////////////////////////////////////////////////////////////
                                ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Insufficient unstaked escrow to facilitate transfer
    /// @param entryID the id of the entry that couldn't be transferred
    /// @param escrowAmount the amount of escrow in the entry
    /// @param unstakedBalance the amount of unstaked escrow in the account
    error InsufficientUnstakedBalance(
        uint256 entryID, uint256 escrowAmount, uint256 unstakedBalance
    );

    /// @notice Attempted to set entry early vesting fee beyond 100%
    error EarlyVestingFeeTooHigh();

    /// @notice error someone other than staking rewards calls an onlyStakingRewards function
    error OnlyStakingRewards();

    /// @notice staking rewards is only allowed to be set once
    error StakingRewardsAlreadySet();

    /// @notice cannot set this value to the zero address
    error ZeroAddress();

    /// @notice cannot mint entries with zero escrow
    error ZeroAmount();

    /// @notice cannot mint entries with zero early vesting fee
    error ZeroEarlyVestingFee();

    /// @notice Must be enough balance in the contract to provide for the vesting entry
    error InsufficientBalance();

    /// @notice Cannot escrow with 0 duration OR above max_duration
    error InvalidDuration();
}
