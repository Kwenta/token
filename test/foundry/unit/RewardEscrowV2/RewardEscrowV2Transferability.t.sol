// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {IRewardEscrowV2} from "../../../../contracts/interfaces/IRewardEscrowV2.sol";
import "../../utils/Constants.t.sol";

contract RewardEscrowV2TransferabilityTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                            Access Control
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Steal_Other_Users_Entries() public {
        // create the escrow entry
        createRewardEscrowEntryV2(user1, 1 ether, 52 weeks);

        // assert user1 has escrowed balance
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), 1 ether);
        assertEq(rewardEscrowV2.balanceOf(user1), 1);

        // attempt to steal other users vesting entry
        uint256 user1EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];
        vm.expectRevert("ERC721: caller is not token owner or approved");
        rewardEscrowV2.transferFrom(user1, user2, user1EntryID);
    }

    function test_Cannot_Steal_Other_Users_Entries_Fuzz(uint32 amount, uint24 duration) public {
        vm.assume(amount > 0);
        vm.assume(duration > 0);

        // create the escrow entry
        createRewardEscrowEntryV2(user1, amount, duration);

        // assert user1 has escrowed balance
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), amount);
        assertEq(rewardEscrowV2.balanceOf(user1), 1);

        // attempt to steal other users vesting entry
        uint256 user1EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];
        vm.expectRevert("ERC721: caller is not token owner or approved");
        rewardEscrowV2.transferFrom(user1, user2, user1EntryID);
    }

    function test_Cannot_Bulk_Steal_Other_Users_Entries() public {
        // create the escrow entry
        createRewardEscrowEntryV2(user1, 1 ether, 52 weeks);

        // assert user1 has escrowed balance
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), 1 ether);
        assertEq(rewardEscrowV2.balanceOf(user1), 1);

        // attempt to steal other users vesting entry
        uint256 user1EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];
        vm.expectRevert("ERC721: caller is not token owner or approved");
        entryIDs.push(user1EntryID);
        rewardEscrowV2.bulkTransferFrom(user1, user2, entryIDs);
    }

    function test_Cannot_Bulk_Steal_Other_Users_Entries_Fuzz(uint32 amount, uint24 duration)
        public
    {
        vm.assume(amount > 0);
        vm.assume(duration > 0);

        // create the escrow entry
        createRewardEscrowEntryV2(user1, amount, duration);

        // assert user1 has escrowed balance
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), amount);
        assertEq(rewardEscrowV2.balanceOf(user1), 1);

        // attempt to steal other users vesting entry
        uint256 user1EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];
        vm.expectRevert("ERC721: caller is not token owner or approved");
        entryIDs.push(user1EntryID);
        rewardEscrowV2.bulkTransferFrom(user1, user2, entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                        Transfer Vesting Entries
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Transfer_Non_Existent_Entry() public {
        vm.expectRevert("ERC721: invalid token ID");
        rewardEscrowV2.transferFrom(address(this), user1, 50);
    }

    function test_Cannot_Transfer_Non_Existent_Entry_Fuzz(uint256 entryID) public {
        vm.assume(entryID > 0);
        vm.expectRevert("ERC721: invalid token ID");
        rewardEscrowV2.transferFrom(address(this), user1, entryID);
    }

    function test_transferFrom_Unstaked() public {
        uint256 escrowAmount = 1 ether;

        // create the escrow entry
        createRewardEscrowEntryV2(user1, escrowAmount, 52 weeks);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount);

        // check starting escrow balances
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), escrowAmount);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user2), 0);

        // assert correct number of entries for each user
        uint256 user1EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];
        assertEq(rewardEscrowV2.balanceOf(user1), 1);
        assertEq(rewardEscrowV2.balanceOf(user2), 0);

        // get initial values
        (
            uint64 initialEndTime,
            uint256 initialEscrowAmount,
            uint256 initialDuration,
            uint8 initialEarlyVestingFee
        ) = rewardEscrowV2.getVestingEntry(user1EntryID);

        // transfer vesting entry from user1 to user2
        vm.prank(user1);
        rewardEscrowV2.transferFrom(user1, user2, user1EntryID);

        // assert that the entry has been passed over to user2
        assertEq(rewardEscrowV2.balanceOf(user1), 0);
        assertEq(rewardEscrowV2.balanceOf(user2), 1);

        // check the right entryID has been transferred
        uint256 user2EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user2, 0, 1)[0];
        assertEq(user1EntryID, user2EntryID);

        // check balances passed over
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), 0);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user2), escrowAmount);

        // check vestingSchedules updated
        (
            uint64 finalEndTime,
            uint256 finalEscrowAmount,
            uint256 finalDuration,
            uint8 finalEarlyVestingFee
        ) = rewardEscrowV2.getVestingEntry(user2EntryID);

        assertEq(finalEndTime, initialEndTime);
        assertEq(finalEscrowAmount, initialEscrowAmount);
        assertEq(finalDuration, initialDuration);
        assertEq(finalEarlyVestingFee, initialEarlyVestingFee);

        // check accountVestingEntryIDs updated
        uint256[] memory user1VestingSchedules =
            rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1);
        uint256[] memory user2VestingSchedules =
            rewardEscrowV2.getAccountVestingEntryIDs(user2, 0, 1);
        assertEq(user1VestingSchedules.length, 0);
        assertEq(user2VestingSchedules.length, 1);
        assertEq(user2VestingSchedules[0], user2EntryID);

        // check totalEscrowedBalance unchanged
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount);
    }

    function test_transferFrom_Unstaked_Fuzz(
        uint32 escrowAmount,
        uint24 duration,
        uint8 numberOfEntries
    ) public {
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
        uint256 user1EntryID =
            rewardEscrowV2.getAccountVestingEntryIDs(user1, entryToTransferIndex, 1)[0];
        assertEq(rewardEscrowV2.balanceOf(user1), numberOfEntries);
        assertEq(rewardEscrowV2.balanceOf(user2), 0);

        // transfer vesting entry from user1 to user2
        vm.prank(user1);
        rewardEscrowV2.transferFrom(user1, user2, user1EntryID);

        // assert that the entry has been passed over to user2
        assertEq(rewardEscrowV2.balanceOf(user1), numberOfEntries - 1);
        assertEq(rewardEscrowV2.balanceOf(user2), 1);

        // check the right entryID has been transferred
        uint256 user2EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user2, 0, 1)[0];
        assertEq(user1EntryID, user2EntryID);

        // check balances passed over
        assertEq(
            rewardEscrowV2.totalEscrowedAccountBalance(user1), totalEscrowedAmount - escrowAmount
        );
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user2), escrowAmount);

        // check accountVestingEntryIDs updated
        uint256[] memory user1VestingSchedules =
            rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, numberOfEntries);
        uint256[] memory user2VestingSchedules =
            rewardEscrowV2.getAccountVestingEntryIDs(user2, 0, numberOfEntries);
        assertEq(user1VestingSchedules.length, numberOfEntries - 1);
        assertEq(user2VestingSchedules.length, 1);
        assertEq(user2VestingSchedules[0], user2EntryID);

        // check totalEscrowedBalance unchanged
        assertEq(rewardEscrowV2.totalEscrowedBalance(), totalEscrowedAmount);
    }

    function test_transferFrom_Insufficient_Unstaked() public {
        uint256 escrowAmount = 1 ether;

        // create the escrow entry
        createRewardEscrowEntryV2(user1, escrowAmount, 52 weeks);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount);

        // stake the escrow
        vm.prank(user1);
        stakingRewardsV2.stakeEscrow(escrowAmount);

        // transfer vesting entry from user1 to user2
        uint256 user1EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];
        vm.prank(user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardEscrowV2.InsufficientUnstakedBalance.selector, user1EntryID, escrowAmount, 0
            )
        );
        rewardEscrowV2.transferFrom(user1, user2, user1EntryID);
    }

    function test_transferFrom_Insufficient_Unstaked_Fuzz(
        uint32 escrowAmount,
        uint32 stakedAmount,
        uint24 duration
    ) public {
        vm.assume(escrowAmount > 0);
        vm.assume(stakedAmount > 0);
        vm.assume(duration > 0);
        vm.assume(escrowAmount >= stakedAmount);

        // create the escrow entry
        createRewardEscrowEntryV2(user1, escrowAmount, duration);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount);

        // stake the escrow
        vm.prank(user1);
        stakingRewardsV2.stakeEscrow(stakedAmount);

        // transfer vesting entry from user1 to user2
        uint256 user1EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];
        vm.prank(user1);

        uint256 unstakedAmount = escrowAmount - stakedAmount;
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardEscrowV2.InsufficientUnstakedBalance.selector,
                user1EntryID,
                escrowAmount,
                unstakedAmount
            )
        );
        rewardEscrowV2.transferFrom(user1, user2, user1EntryID);
    }

    function test_transferFrom_To_Self() public {
        uint256 escrowAmount = 1 ether;

        // create the escrow entry
        createRewardEscrowEntryV2(user1, escrowAmount, 52 weeks);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount);

        // check starting escrow balances
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), escrowAmount);

        // assert correct number of entries for each user
        uint256 user1EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];
        assertEq(rewardEscrowV2.balanceOf(user1), 1);

        // get initial values
        (
            uint64 initialEndTime,
            uint256 initialEscrowAmount,
            uint256 initialDuration,
            uint8 initialEarlyVestingFee
        ) = rewardEscrowV2.getVestingEntry(user1EntryID);

        // transfer vesting entry to self
        vm.prank(user1);
        rewardEscrowV2.transferFrom(user1, user1, user1EntryID);

        // assert that the entry is still owned by user1
        assertEq(rewardEscrowV2.balanceOf(user1), 1);

        // check the right entryID is still owned
        uint256 user1EntryIDAfter = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];
        assertEq(user1EntryID, user1EntryIDAfter);

        // check balances unchanged
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), escrowAmount);

        // check vestingSchedules unchanged
        (
            uint64 finalEndTime,
            uint256 finalEscrowAmount,
            uint256 finalDuration,
            uint8 finalEarlyVestingFee
        ) = rewardEscrowV2.getVestingEntry(user1EntryID);

        assertEq(finalEndTime, initialEndTime);
        assertEq(finalEscrowAmount, initialEscrowAmount);
        assertEq(finalDuration, initialDuration);
        assertEq(finalEarlyVestingFee, initialEarlyVestingFee);

        // check accountVestingEntryIDs unchanged
        uint256[] memory user1VestingSchedules =
            rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1);
        assertEq(user1VestingSchedules.length, 1);
        assertEq(user1VestingSchedules[0], user1EntryID);

        // check totalEscrowedBalance unchanged
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount);
    }

    /*//////////////////////////////////////////////////////////////
                    Bulk Transfer Vesting Entries
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Bulk_Transfer_Non_Existent_Entry() public {
        vm.expectRevert("ERC721: invalid token ID");
        entryIDs.push(50);
        rewardEscrowV2.bulkTransferFrom(address(this), user1, entryIDs);
    }

    function test_Cannot_Bulk_Transfer_Non_Existent_Entry_Fuzz(uint256 entryID) public {
        vm.assume(entryID > 0);
        entryIDs.push(entryID);
        vm.expectRevert("ERC721: invalid token ID");
        rewardEscrowV2.bulkTransferFrom(address(this), user1, entryIDs);
    }

    function test_bulkTransferFrom_Unstaked() public {
        uint256 escrowAmount = 1 ether;

        // create the escrow entry
        createRewardEscrowEntryV2(user1, escrowAmount, 52 weeks);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount);

        // check starting escrow balances
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), escrowAmount);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user2), 0);

        // assert correct number of entries for each user
        uint256 user1EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];
        assertEq(rewardEscrowV2.balanceOf(user1), 1);
        assertEq(rewardEscrowV2.balanceOf(user2), 0);

        // get initial values
        (
            uint64 initialEndTime,
            uint256 initialEscrowAmount,
            uint256 initialDuration,
            uint8 initialEarlyVestingFee
        ) = rewardEscrowV2.getVestingEntry(user1EntryID);

        // transfer vesting entry from user1 to user2
        vm.prank(user1);
        entryIDs.push(user1EntryID);
        rewardEscrowV2.bulkTransferFrom(user1, user2, entryIDs);

        // assert that the entry has been passed over to user2
        assertEq(rewardEscrowV2.balanceOf(user1), 0);
        assertEq(rewardEscrowV2.balanceOf(user2), 1);

        // check the right entryID has been transferred
        uint256 user2EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user2, 0, 1)[0];
        assertEq(user1EntryID, user2EntryID);

        // check balances passed over
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), 0);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user2), escrowAmount);

        // check vestingSchedules updated
        (
            uint64 finalEndTime,
            uint256 finalEscrowAmount,
            uint256 finalDuration,
            uint8 finalEarlyVestingFee
        ) = rewardEscrowV2.getVestingEntry(user2EntryID);

        assertEq(finalEndTime, initialEndTime);
        assertEq(finalEscrowAmount, initialEscrowAmount);
        assertEq(finalDuration, initialDuration);
        assertEq(finalEarlyVestingFee, initialEarlyVestingFee);

        // check accountVestingEntryIDs updated
        uint256[] memory user1VestingSchedules =
            rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1);
        uint256[] memory user2VestingSchedules =
            rewardEscrowV2.getAccountVestingEntryIDs(user2, 0, 1);
        assertEq(user1VestingSchedules.length, 0);
        assertEq(user2VestingSchedules.length, 1);
        assertEq(user2VestingSchedules[0], user2EntryID);

        // check totalEscrowedBalance unchanged
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount);
    }

    function test_bulkTransferFrom_Series_Unstaked_Fuzz(
        uint32 escrowAmount,
        uint24 duration,
        uint8 numberOfEntries
    ) public {
        vm.assume(escrowAmount > 0);
        vm.assume(duration > 0);
        vm.assume(numberOfEntries > 0);

        uint256 totalEscrowedAmount;
        uint256 startingEntryToTransferIndex =
            getPseudoRandomNumber(numberOfEntries - 1, 0, escrowAmount);
        uint256 endingEntryToTransferIndex =
            getPseudoRandomNumber(numberOfEntries - 1, startingEntryToTransferIndex, escrowAmount);
        uint256 numberOfEntriesTransferred =
            endingEntryToTransferIndex - startingEntryToTransferIndex + 1;

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
        uint256 firstEntryTransferredID =
            rewardEscrowV2.getAccountVestingEntryIDs(user1, startingEntryToTransferIndex, 1)[0];
        assertEq(rewardEscrowV2.balanceOf(user1), numberOfEntries);
        assertEq(rewardEscrowV2.balanceOf(user2), 0);

        // add entryIDs to list for bulk transfer
        for (uint256 i = 0; i < numberOfEntriesTransferred; ++i) {
            entryIDs.push(firstEntryTransferredID + i);
        }

        vm.prank(user1);
        rewardEscrowV2.bulkTransferFrom(user1, user2, entryIDs);

        // assert that the entries have been passed over to user2
        assertEq(rewardEscrowV2.balanceOf(user1), numberOfEntries - numberOfEntriesTransferred);
        assertEq(rewardEscrowV2.balanceOf(user2), numberOfEntriesTransferred);

        // check the right entryIDs have been transferred
        for (uint256 i = 0; i < numberOfEntriesTransferred; ++i) {
            uint256 user2EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user2, i, 1)[0];
            assertEq(firstEntryTransferredID + i, user2EntryID);
        }

        // check balances passed over
        uint256 amountTransferred = escrowAmount * numberOfEntriesTransferred;
        assertEq(
            rewardEscrowV2.totalEscrowedAccountBalance(user1),
            totalEscrowedAmount - amountTransferred
        );
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user2), amountTransferred);

        // check accountVestingEntryIDs updated
        uint256[] memory user1VestingSchedules =
            rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, numberOfEntries);
        uint256[] memory user2VestingSchedules =
            rewardEscrowV2.getAccountVestingEntryIDs(user2, 0, numberOfEntries);
        assertEq(user1VestingSchedules.length, numberOfEntries - numberOfEntriesTransferred);
        assertEq(user2VestingSchedules.length, numberOfEntriesTransferred);

        // check totalEscrowedBalance unchanged
        assertEq(rewardEscrowV2.totalEscrowedBalance(), totalEscrowedAmount);
    }

    function test_bulkTransferFrom_Random_Selection_Unstaked_Fuzz(
        uint32 escrowAmount,
        uint24 duration,
        uint8 numberOfEntries
    ) public {
        vm.assume(escrowAmount > 0);
        vm.assume(duration > 0);
        vm.assume(numberOfEntries > 0);

        uint256 totalEscrowedAmount;

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
        assertEq(rewardEscrowV2.balanceOf(user1), numberOfEntries);
        assertEq(rewardEscrowV2.balanceOf(user2), 0);

        // add random selection of entryIDs to list for bulk transfer
        for (uint256 i = 0; i < numberOfEntries; ++i) {
            if (flipCoin()) {
                entryIDs.push(i + 1);
            }
        }

        vm.prank(user1);
        rewardEscrowV2.bulkTransferFrom(user1, user2, entryIDs);

        // assert that the entries have been passed over to user2
        assertEq(rewardEscrowV2.balanceOf(user1), numberOfEntries - entryIDs.length);
        assertEq(rewardEscrowV2.balanceOf(user2), entryIDs.length);

        // check the right entryIDs have been transferred
        for (uint256 i = 0; i < entryIDs.length; ++i) {
            uint256 user2EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user2, i, 1)[0];
            assertEq(entryIDs[i], user2EntryID);
        }

        // check balances passed over
        uint256 amountTransferred = escrowAmount * entryIDs.length;
        assertEq(
            rewardEscrowV2.totalEscrowedAccountBalance(user1),
            totalEscrowedAmount - amountTransferred
        );
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user2), amountTransferred);

        // check accountVestingEntryIDs updated
        uint256[] memory user1VestingSchedules =
            rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, numberOfEntries);
        uint256[] memory user2VestingSchedules =
            rewardEscrowV2.getAccountVestingEntryIDs(user2, 0, numberOfEntries);
        assertEq(user1VestingSchedules.length, numberOfEntries - entryIDs.length);
        assertEq(user2VestingSchedules.length, entryIDs.length);

        // check totalEscrowedBalance unchanged
        assertEq(rewardEscrowV2.totalEscrowedBalance(), totalEscrowedAmount);
    }

    function test_bulkTransferFrom_Insufficient_Unstaked() public {
        uint256 escrowAmount = 1 ether;

        // create the escrow entry
        createRewardEscrowEntryV2(user1, escrowAmount, 52 weeks);
        createRewardEscrowEntryV2(user1, escrowAmount, 52 weeks);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount * 2);

        // stake half the escrow
        vm.prank(user1);
        stakingRewardsV2.stakeEscrow(escrowAmount);

        // transfer vesting entry from user1 to user2
        uint256 user1EntryIDA = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 2)[0];
        uint256 user1EntryIDB = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 2)[1];
        vm.prank(user1);

        entryIDs.push(user1EntryIDA);
        entryIDs.push(user1EntryIDB);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardEscrowV2.InsufficientUnstakedBalance.selector, user1EntryIDB, escrowAmount, 0
            )
        );
        rewardEscrowV2.bulkTransferFrom(user1, user2, entryIDs);
    }

    function test_bulkTransferFrom_Insufficient_Unstaked_Fuzz(
        uint32 _escrowAmount,
        uint32 _stakedAmount,
        uint24 _duration,
        uint8 _numberOfEntries
    ) public {
        uint256 escrowAmount = _escrowAmount;
        uint256 stakedAmount = _stakedAmount;
        uint256 duration = _duration;
        uint256 numberOfEntries = _numberOfEntries;

        vm.assume(escrowAmount > 0);
        vm.assume(stakedAmount > 0);
        vm.assume(duration > 0);
        vm.assume(numberOfEntries > 0);
        vm.assume(escrowAmount * numberOfEntries >= stakedAmount);

        uint256 unstakedAmount = (escrowAmount * numberOfEntries) - stakedAmount;
        uint256 totalEscrowedAmount;
        uint256 indexAtFailure;
        bool indexFound;

        // create the escrow entry
        for (uint256 i = 0; i < numberOfEntries; ++i) {
            createRewardEscrowEntryV2(user1, escrowAmount, duration);
            totalEscrowedAmount += escrowAmount;
            if (!indexFound && totalEscrowedAmount > unstakedAmount) {
                indexAtFailure = i;
                indexFound = true;
            }
        }

        assertEq(rewardEscrowV2.totalEscrowedBalance(), totalEscrowedAmount);

        // calculate the unstaked balance at failure
        uint256 escrowedBalanceAtFailure = totalEscrowedAmount - (indexAtFailure * escrowAmount);
        uint256 unstakedBalanceAtFailure = escrowedBalanceAtFailure - stakedAmount;

        // stake the escrow
        vm.prank(user1);
        stakingRewardsV2.stakeEscrow(stakedAmount);

        // add entryIDs to list for bulk transfer
        for (uint256 i = 0; i < numberOfEntries; ++i) {
            entryIDs.push(1 + i);
        }

        // assert bulk transfer failure with insufficient unstaked balance
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IRewardEscrowV2.InsufficientUnstakedBalance.selector,
                indexAtFailure + 1,
                escrowAmount,
                unstakedBalanceAtFailure
            )
        );
        rewardEscrowV2.bulkTransferFrom(user1, user2, entryIDs);
    }

    function test_bulkTransferFrom_To_Self() public {
        uint256 escrowAmount = 1 ether;

        // create the escrow entry
        createRewardEscrowEntryV2(user1, escrowAmount, 52 weeks);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount);

        // check starting escrow balances
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), escrowAmount);

        // assert correct number of entries for each user
        uint256 user1EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];
        assertEq(rewardEscrowV2.balanceOf(user1), 1);

        // get initial values
        (
            uint64 initialEndTime,
            uint256 initialEscrowAmount,
            uint256 initialDuration,
            uint8 initialEarlyVestingFee
        ) = rewardEscrowV2.getVestingEntry(user1EntryID);

        // bulk transfer vesting entries to self
        entryIDs.push(user1EntryID);
        vm.prank(user1);
        rewardEscrowV2.bulkTransferFrom(user1, user1, entryIDs);

        // assert that the entry is still owned by user1
        assertEq(rewardEscrowV2.balanceOf(user1), 1);

        // check the right entryID is still owned
        uint256 user1EntryIDAfter = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];
        assertEq(user1EntryID, user1EntryIDAfter);

        // check balances unchanged
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(user1), escrowAmount);

        // check vestingSchedules unchanged
        (
            uint64 finalEndTime,
            uint256 finalEscrowAmount,
            uint256 finalDuration,
            uint8 finalEarlyVestingFee
        ) = rewardEscrowV2.getVestingEntry(user1EntryID);

        assertEq(finalEndTime, initialEndTime);
        assertEq(finalEscrowAmount, initialEscrowAmount);
        assertEq(finalDuration, initialDuration);
        assertEq(finalEarlyVestingFee, initialEarlyVestingFee);

        // check accountVestingEntryIDs unchanged
        uint256[] memory user1VestingSchedules =
            rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1);
        assertEq(user1VestingSchedules.length, 1);
        assertEq(user1VestingSchedules[0], user1EntryID);

        // check totalEscrowedBalance unchanged
        assertEq(rewardEscrowV2.totalEscrowedBalance(), escrowAmount);
    }

    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    function test_transferFrom_Event() public {
        uint256 escrowAmount = 1 ether;

        // create the escrow entry
        createRewardEscrowEntryV2(user1, escrowAmount, 52 weeks);
        uint256 user1EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];

        // transfer vesting entry from user1 to user2
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit Transfer(user1, user2, user1EntryID);
        rewardEscrowV2.transferFrom(user1, user2, user1EntryID);
    }

    function test_transferFrom_Event_Fuzz(
        uint32 escrowAmount,
        uint24 duration,
        uint8 numberOfEntries
    ) public {
        vm.assume(escrowAmount > 0);
        vm.assume(duration > 0);
        vm.assume(numberOfEntries > 0);

        // create the escrow entries
        for (uint256 i = 0; i < numberOfEntries; ++i) {
            createRewardEscrowEntryV2(user1, escrowAmount, duration);
        }

        // transfer vesting entry from user1 to user2
        uint256 entryToTransferIndex = getPseudoRandomNumber(numberOfEntries - 1, 0, escrowAmount);
        uint256 user1EntryID =
            rewardEscrowV2.getAccountVestingEntryIDs(user1, entryToTransferIndex, 1)[0];
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit Transfer(user1, user2, user1EntryID);
        rewardEscrowV2.transferFrom(user1, user2, user1EntryID);
    }

    function test_bulkTransferFrom_Events() public {
        uint256 escrowAmount = 1 ether;

        // create the escrow entry
        createRewardEscrowEntryV2(user1, escrowAmount, 52 weeks);
        uint256 user1EntryID = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 1)[0];

        // transfer vesting entry from user1 to user2
        entryIDs.push(user1EntryID);
        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit Transfer(user1, user2, user1EntryID);
        rewardEscrowV2.bulkTransferFrom(user1, user2, entryIDs);
    }

    function test_bulkTransferFrom_Events_Fuzz(
        uint32 escrowAmount,
        uint24 duration,
        uint8 numberOfEntries
    ) public {
        vm.assume(escrowAmount > 0);
        vm.assume(duration > 0);
        vm.assume(numberOfEntries > 0);

        // create the escrow entries
        for (uint256 i = 0; i < numberOfEntries; ++i) {
            createRewardEscrowEntryV2(user1, escrowAmount, duration);
            entryIDs.push(i + 1);
        }

        // transfer vesting entries from user1 to user2
        for (uint256 i = 0; i < numberOfEntries; ++i) {
            vm.expectEmit(true, true, true, true);
            emit Transfer(user1, user2, i + 1);
        }
        vm.prank(user1);
        rewardEscrowV2.bulkTransferFrom(user1, user2, entryIDs);
    }
}
