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
        uint64 endTime;
        uint256 escrowAmount;
        uint256 entryID;
    }
}

interface IRewardEscrowV2 {
    // Views
    function getKwentaAddress() external view returns (address);

    function totalEscrowBalanceOf(address account) external view returns (uint256);

    function unstakedEscrowBalanceOf(address account) external view returns (uint256);

    function totalEscrowedAccountBalance(address account) external view returns (uint256);

    function totalVestedAccountBalance(address account) external view returns (uint256);

    function getVestingQuantity(uint256[] calldata entryIDs)
        external
        view
        returns (uint256, uint256);

    function getVestingSchedules(address account, uint256 index, uint256 pageSize)
        external
        view
        returns (VestingEntries.VestingEntryWithID[] memory);

    function getAccountVestingEntryIDs(address account, uint256 index, uint256 pageSize)
        external
        view
        returns (uint256[] memory);

    function getVestingEntryClaimable(uint256 entryID) external view returns (uint256, uint256);

    function getVestingEntry(uint256 entryID)
        external
        view
        returns (uint64, uint256, uint256, uint8);

    // Mutative functions
    function vest(uint256[] calldata entryIDs) external;

    function createEscrowEntry(
        address beneficiary,
        uint256 deposit,
        uint256 duration,
        uint8 earlyVestingFee
    ) external;

    function appendVestingEntry(address account, uint256 quantity, uint256 duration) external;

    function stakeEscrow(uint256 _amount) external;

    function unstakeEscrow(uint256 _amount) external;

    function bulkTransferFrom(address from, address to, uint256[] calldata entryIDs) external;

    /* ========== EVENTS ========== */
    event Vested(address indexed beneficiary, uint256 value);
    event VestingEntryCreated(
        address indexed beneficiary, uint256 value, uint256 duration, uint256 entryID
    );
    event StakingRewardsSet(address stakingRewardsV2);
    event TreasuryDAOSet(address treasuryDAO);

    // Errors
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
