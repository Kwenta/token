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

    function totalEscrowedAccountBalance(address account)
        external
        view
        returns (uint256);

    function totalVestedAccountBalance(address account)
        external
        view
        returns (uint256);

    function getVestingQuantity(uint256[] calldata entryIDs)
        external
        view
        returns (uint256, uint256);

    function getVestingSchedules(
        address account,
        uint256 index,
        uint256 pageSize
    ) external view returns (VestingEntries.VestingEntryWithID[] memory);

    function getAccountVestingEntryIDs(
        address account,
        uint256 index,
        uint256 pageSize
    ) external view returns (uint256[] memory);

    function getVestingEntryClaimable(uint256 entryID)
        external
        view
        returns (uint256, uint256);

    function getVestingEntry(uint256 entryID)
        external
        view
        returns (
            uint64,
            uint256,
            uint256,
            uint8
        );

    // Mutative functions
    function vest(uint256[] calldata entryIDs) external;

    function createEscrowEntry(
        address beneficiary,
        uint256 deposit,
        uint256 duration,
        uint8 earlyVestingFee
    ) external;

    function appendVestingEntry(
        address account,
        uint256 quantity,
        uint256 duration
    ) external;

    function stakeEscrow(uint256 _amount) external;

    function unstakeEscrow(uint256 _amount) external;

    function transferVestingEntry(uint256 entryID, address account) external;

    // Errors
    /// @notice An invalid entryID was provided
    /// @param entryID The id of the invalid entry
    error InvalidEntry(uint256 entryID);

    /// @notice Attempted to transfer an entry that is not yours
    /// @param entryID The id of the non-owned entry
    /// @dev msg.sender must be the owner of the entry
    error NotYourEntry(uint256 entryID);

    /// @notice Insufficient unstaked escrow to facilitate transfer
    /// @param entryID the id of the entry that couldn't be transferred
    /// @param escrowAmount the amount of escrow in the entry
    /// @param unstakedBalance the amount of unstaked escrow in the account
    error InsufficientUnstakedBalance(uint256 entryID, uint256 escrowAmount, uint256 unstakedBalance);

    /// @notice Attempted to set entry early vesting fee beyond 100%
    error MaxEarlyVestingFeeIs100();
}
