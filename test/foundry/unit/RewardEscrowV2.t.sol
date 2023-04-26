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

        // assert user1 has some escrow balance
        uint256 user1EscrowedAccountBalance = rewardEscrowV2.totalEscrowedAccountBalance(user1);
        assertEq(user1EscrowedAccountBalance, 1 ether);

        // get vesting entry ids
        uint256 user1NumOfEntryIDs = rewardEscrowV2.numVestingEntries(user1);
        uint256 user1EntryID = rewardEscrowV2.accountVestingEntryIDs(user1, 0);

        // confirm user1 does have an entry
        assertEq(user1NumOfEntryIDs, 1);

        // attempt to steal other users vesting entry
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

    function test_transferVestingEntry_Unstaked() public {
        // create the escrow entry
        createRewardEscrowEntryV2(user1, 1 ether, 52 weeks);

        // check starting escrow balances
        uint256 user1EscrowedAccountBalance = rewardEscrowV2.totalEscrowedAccountBalance(user1);
        uint256 user2EscrowedAccountBalance = rewardEscrowV2.totalEscrowedAccountBalance(user2);
        assertEq(user1EscrowedAccountBalance, 1 ether);
        assertEq(user2EscrowedAccountBalance, 0);

        // assert correct number of entries for each user
        uint256 user1NumOfEntryIDs = rewardEscrowV2.numVestingEntries(user1);
        uint256 user2NumOfEntryIDs = rewardEscrowV2.numVestingEntries(user2);
        uint256 user1EntryID = rewardEscrowV2.accountVestingEntryIDs(user1, 0);
        assertEq(user1NumOfEntryIDs, 1);
        assertEq(user2NumOfEntryIDs, 0);

        // get initial values
        (uint64 initialEndTime, uint256 initialEscrowAmount, uint256 initialDuration) =
            rewardEscrowV2.getVestingEntry(user1, user1EntryID);

        // transfer vesting entry from user1 to user2
        vm.prank(user1);
        rewardEscrowV2.transferVestingEntry(user1EntryID, user2);

        // assert that the entry has been passed over to user2
        user1NumOfEntryIDs = rewardEscrowV2.numVestingEntries(user1);
        user2NumOfEntryIDs = rewardEscrowV2.numVestingEntries(user2);
        assertEq(user1NumOfEntryIDs, 0);
        assertEq(user2NumOfEntryIDs, 1);

        // check the right entryID has been transferred
        uint256 user2EntryID = rewardEscrowV2.accountVestingEntryIDs(user2, 0);
        assertEq(user1EntryID, user2EntryID);

        // check balances passed over
        user1EscrowedAccountBalance = rewardEscrowV2.totalEscrowedAccountBalance(user1);
        user2EscrowedAccountBalance = rewardEscrowV2.totalEscrowedAccountBalance(user2);
        assertEq(user1EscrowedAccountBalance, 0);
        assertEq(user2EscrowedAccountBalance, 1 ether);

        // check vestingSchedules updated
        (uint64 finalEndTime, uint256 finalEscrowAmount, uint256 finalDuration) =
            rewardEscrowV2.getVestingEntry(user2, user2EntryID);

        assertEq(finalEndTime, initialEndTime);
        assertEq(finalEscrowAmount, initialEscrowAmount);
        assertEq(finalDuration, initialDuration);

        // check accountVestingEntryIDs updated
        // check totalEscrowedBalance unchanged
    }

    // TODO: test changes in accountVestingEntryIDs
    // TODO: test for larger numbers of vesting entries -> ensure loop and swap works
    // TODO: test changes in vestingSchedules
    // TODO: test staked escrow
    // TODO: test mix of staked and unstaked escrow entries
    // TODO: test staked escrow before cooldown is complete
    // TODO: test staked escrow before after is complete
    // TODO: add efficient transferAllVestingEntries(account) or transferXVestingEntries(numEntries, account)
    //          - perhaps not needed if bulkTransferVestingEntries is handled appropriately???
    // TODO: what happens if someone transfers an entry to themselves?
}
