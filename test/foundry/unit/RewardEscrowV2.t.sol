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

    function test_Cannot_Transfer_Other_Users_Entries() public {
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
        // vm.expectRevert();
        rewardEscrowV2.transferVestingEntry(user1EntryID, user2);
    }

    /*//////////////////////////////////////////////////////////////
                        Transfer Vesting Entries
    //////////////////////////////////////////////////////////////*/

    function test_transferVestingEntry_Unstaked() public {
        // create the escrow entry
        createRewardEscrowEntryV2(user1, 1 ether, 52 weeks);

        // get escrowed balances
        uint256 user1EscrowedAccountBalance = rewardEscrowV2.totalEscrowedAccountBalance(user1);
        uint256 user2EscrowedAccountBalance = rewardEscrowV2.totalEscrowedAccountBalance(user2);

        // user1 has some escrow balance
        assertEq(user1EscrowedAccountBalance, 1 ether);

        // user2 has no escrow balance
        assertEq(user2EscrowedAccountBalance, 0);

        // get vesting entry ids
        uint256 user1NumOfEntryIDs = rewardEscrowV2.numVestingEntries(user1);
        uint256 user2NumOfEntryIDs = rewardEscrowV2.numVestingEntries(user2);
        uint256 user1EntryID = rewardEscrowV2.accountVestingEntryIDs(user1, 0);

        // assert correct number of entries for each user
        assertEq(user1NumOfEntryIDs, 1);
        assertEq(user2NumOfEntryIDs, 0);

        // transfer vesting entry from user1 to user2
        vm.prank(user1);
        rewardEscrowV2.transferVestingEntry(user1EntryID, user2);

        // get new number of entries
        user1NumOfEntryIDs = rewardEscrowV2.numVestingEntries(user1);
        user2NumOfEntryIDs = rewardEscrowV2.numVestingEntries(user2);

        // assert that the entry has been passed over to user2
        assertEq(user1NumOfEntryIDs, 0);
        assertEq(user2NumOfEntryIDs, 1);

        uint256 user2EntryID = rewardEscrowV2.accountVestingEntryIDs(user2, 0);
        assertEq(user1EntryID, user2EntryID);

        // get escrowed balances
        user1EscrowedAccountBalance = rewardEscrowV2.totalEscrowedAccountBalance(user1);
        user2EscrowedAccountBalance = rewardEscrowV2.totalEscrowedAccountBalance(user2);

        // user1 has no escrow balance
        assertEq(user1EscrowedAccountBalance, 0);

        // user2 has some escrow balance
        assertEq(user2EscrowedAccountBalance, 1 ether);
    }

    // TODO: test access control
    // TODO: test entry id does not exist
    // TODO: test changes in totalVestedAccountBlaance
    // TODO: test changes in accountVestingEntryIDs
    // TODO: test changes in vestingSchedules
    // TODO: test staked escrow
    // TODO: test mix of staked and unstaked escrow entries
    // TODO: test staked escrow before cooldown is complete
    // TODO: test staked escrow before after is complete
    // TODO: add efficient transferAllVestingEntries(account) or transferXVestingEntries(numEntries, account)
    //          - perhaps not needed if bulkTransferVestingEntries is handled appropriately???
    // TODO: what happens if someone transfers an entry to themselves?

}
