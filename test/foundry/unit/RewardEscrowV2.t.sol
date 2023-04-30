// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DefaultStakingRewardsV2Setup} from "../utils/DefaultStakingRewardsV2Setup.t.sol";
import {IRewardEscrowV2} from "../../../contracts/interfaces/IRewardEscrowV2.sol";
import "../utils/Constants.t.sol";

contract RewardEscrowV2Tests is DefaultStakingRewardsV2Setup {
    /*//////////////////////////////////////////////////////////////
                            Access Control
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Steal_Other_Users_Entries() public {
        // create the escrow entry
        createRewardEscrowEntryV2(user1, 1 ether, 52 weeks);

        // assert user1 has escrowed balance
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), 1 ether);
        assertEq(rewardEscrowV2.numVestingEntries(user1), 1);

        // attempt to steal other users vesting entry
        uint256 user1EntryID = rewardEscrowV2.accountVestingEntryIDs(user1, 0);
        vm.expectRevert(abi.encodeWithSelector(IRewardEscrowV2.NotYourEntry.selector, user1EntryID));
        rewardEscrowV2.transferVestingEntry(user1EntryID, user2);
    }

    function test_Cannot_Steal_Other_Users_Entries_Fuzz(uint32 amount, uint24 duration) public {
        vm.assume(amount > 0);
        vm.assume(duration > 0);

        // create the escrow entry
        createRewardEscrowEntryV2(user1, amount, duration);

        // assert user1 has escrowed balance
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), amount);
        assertEq(rewardEscrowV2.numVestingEntries(user1), 1);

        // attempt to steal other users vesting entry
        uint256 user1EntryID = rewardEscrowV2.accountVestingEntryIDs(user1, 0);
        vm.expectRevert(abi.encodeWithSelector(IRewardEscrowV2.NotYourEntry.selector, user1EntryID));
        rewardEscrowV2.transferVestingEntry(user1EntryID, user2);
    }

    /*//////////////////////////////////////////////////////////////
                        Transfer Vesting Entries
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Transfer_Non_Existent_Entry() public {
        vm.expectRevert(abi.encodeWithSelector(IRewardEscrowV2.InvalidEntry.selector, 50));
        rewardEscrowV2.transferVestingEntry(50, user1);
    }

    function test_Cannot_Transfer_Non_Existent_Entry_Fuzz(uint256 entryID) public {
        vm.assume(entryID > 0);
        vm.expectRevert(abi.encodeWithSelector(IRewardEscrowV2.InvalidEntry.selector, entryID));
        rewardEscrowV2.transferVestingEntry(entryID, user1);
    }

    function test_transferVestingEntry_Unstaked() public {
        uint256 escrowAmount = 1 ether;

        // create the escrow entry
        createRewardEscrowEntryV2(user1, escrowAmount, 52 weeks);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount);

        // check starting escrow balances
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), escrowAmount);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user2), 0);

        // assert correct number of entries for each user
        uint256 user1EntryID = rewardEscrowV2.accountVestingEntryIDs(user1, 0);
        assertEq(rewardEscrowV2.numVestingEntries(user1), 1);
        assertEq(rewardEscrowV2.numVestingEntries(user2), 0);

        // get initial values
        (uint64 initialEndTime, uint256 initialEscrowAmount, uint256 initialDuration) =
            rewardEscrowV2.getVestingEntry(user1, user1EntryID);

        // transfer vesting entry from user1 to user2
        vm.prank(user1);
        rewardEscrowV2.transferVestingEntry(user1EntryID, user2);

        // assert that the entry has been passed over to user2
        assertEq(rewardEscrowV2.numVestingEntries(user1), 0);
        assertEq(rewardEscrowV2.numVestingEntries(user2), 1);

        // check the right entryID has been transferred
        uint256 user2EntryID = rewardEscrowV2.accountVestingEntryIDs(user2, 0);
        assertEq(user1EntryID, user2EntryID);

        // check balances passed over
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), 0);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user2), escrowAmount);

        // check vestingSchedules updated
        (uint64 finalEndTime, uint256 finalEscrowAmount, uint256 finalDuration) =
            rewardEscrowV2.getVestingEntry(user2, user2EntryID);

        assertEq(finalEndTime, initialEndTime);
        assertEq(finalEscrowAmount, initialEscrowAmount);
        assertEq(finalDuration, initialDuration);

        // check accountVestingEntryIDs updated
        uint256[] memory user1VestingSchedules = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1);
        uint256[] memory user2VestingSchedules = rewardEscrowV2.getAccountVestingEntryIDs(user2, 0, 1);
        assertEq(user1VestingSchedules.length, 0);
        assertEq(user2VestingSchedules.length, 1);
        assertEq(user2VestingSchedules[0], user2EntryID);

        // check totalEscrowedBalance unchanged
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount);
    }

    function test_transferVestingEntry_Unstaked_Fuzz(uint32 escrowAmount, uint24 duration, uint8 numberOfEntries)
        public
    {
        vm.assume(escrowAmount > 0);
        vm.assume(duration > 0);
        vm.assume(numberOfEntries > 0);

        uint256 totalEscrowedAmount;
        uint256 entryToTransferIndex = getPseudoRandomNumber(numberOfEntries - 1, 0, escrowAmount);

        // create the escrow entry
        for (uint256 i = 0; i < numberOfEntries; ++i) {
            createRewardEscrowEntryV2(user1, escrowAmount, duration);
            totalEscrowedAmount += escrowAmount;
        }

        // check starting escrow balances
        assertEq(rewardEscrowV2.totalEscrowedBalance(), totalEscrowedAmount);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), totalEscrowedAmount);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user2), 0);

        // assert correct number of entries for each user
        uint256 user1EntryID = rewardEscrowV2.accountVestingEntryIDs(user1, entryToTransferIndex);
        assertEq(rewardEscrowV2.numVestingEntries(user1), numberOfEntries);
        assertEq(rewardEscrowV2.numVestingEntries(user2), 0);

        // transfer vesting entry from user1 to user2
        vm.prank(user1);
        rewardEscrowV2.transferVestingEntry(user1EntryID, user2);

        // assert that the entry has been passed over to user2
        assertEq(rewardEscrowV2.numVestingEntries(user1), numberOfEntries - 1);
        assertEq(rewardEscrowV2.numVestingEntries(user2), 1);

        // check the right entryID has been transferred
        uint256 user2EntryID = rewardEscrowV2.accountVestingEntryIDs(user2, 0);
        assertEq(user1EntryID, user2EntryID);

        // check balances passed over
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), totalEscrowedAmount - escrowAmount);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user2), escrowAmount);

        // check accountVestingEntryIDs updated
        uint256[] memory user1VestingSchedules = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, numberOfEntries);
        uint256[] memory user2VestingSchedules = rewardEscrowV2.getAccountVestingEntryIDs(user2, 0, numberOfEntries);
        assertEq(user1VestingSchedules.length, numberOfEntries - 1);
        assertEq(user2VestingSchedules.length, 1);
        assertEq(user2VestingSchedules[0], user2EntryID);

        // check totalEscrowedBalance unchanged
        assertEq(rewardEscrowV2.totalEscrowedBalance(), totalEscrowedAmount);
    }

    function test_transferVestingEntry_Insufficient_Unstaked() public {
        uint256 escrowAmount = 1 ether;

        // create the escrow entry
        createRewardEscrowEntryV2(user1, escrowAmount, 52 weeks);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount);

        // stake the escrow
        vm.prank(user1);
        rewardEscrowV2.stakeEscrow(escrowAmount);

        // transfer vesting entry from user1 to user2
        uint256 user1EntryID = rewardEscrowV2.accountVestingEntryIDs(user1, 0);
        vm.prank(user1);
        // vm.expectRevert(RewardEscrowV2.InsufficientUnstakedBalance.selector);
        vm.expectRevert(abi.encodeWithSelector(IRewardEscrowV2.InsufficientUnstakedBalance.selector, user1EntryID));
        rewardEscrowV2.transferVestingEntry(user1EntryID, user2);
    }

    // TODO: update tests to use view functions instead of state directly
    // TODO: test for larger numbers of vesting entries -> ensure loop and swap works
    // TODO: test changes in vestingSchedules
    // TODO: test staked escrow
    // TODO: test mix of staked and unstaked escrow entries
    // TODO: test staked escrow before cooldown is complete
    // TODO: test staked escrow before after is complete
    // TODO: add efficient transferAllVestingEntries(account) or transferXVestingEntries(numEntries, account)
    //          - perhaps not needed if bulkTransferVestingEntries is handled appropriately???
    // TODO: what happens if someone transfers an entry to themselves?
    // TODO: add and test event
}
