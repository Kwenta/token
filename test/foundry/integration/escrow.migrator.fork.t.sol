// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "../utils/helpers/StakingTestHelpers.t.sol";
import {Migrate} from "../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {VestingEntries} from "../../../contracts/interfaces/IRewardEscrow.sol";
import {IEscrowMigrator} from "../../../contracts/interfaces/IEscrowMigrator.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {EscrowMigrator} from "../../../contracts/EscrowMigrator.sol";
import "../utils/Constants.t.sol";
import {EscrowMigratorTestHelpers} from "../utils/helpers/EscrowMigratorTestHelpers.t.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StakingV2MigrationForkTests is EscrowMigratorTestHelpers {
    /*//////////////////////////////////////////////////////////////
                              STEP 1 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Step_1_Normal() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // check final state
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Step_1_Two_Rounds() public {
        // check initial state
        (uint256[] memory _entryIDs, uint256 numVestingEntries) = claimAndCheckInitialState(user1);

        // step 1.1 - transfer some entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // step 1.2 - transfer some more entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 10, 7);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, numVestingEntries);
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Step_1_Three_Rounds() public {
        // check initial state
        (uint256[] memory _entryIDs, uint256 numVestingEntries) = claimAndCheckInitialState(user1);

        // step 1.1 - transfer some entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 5);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // step 1.2 - transfer some more entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 5, 5);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // step 1.3 - transfer some more entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 10, 7);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, numVestingEntries);
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Step_1_N_Rounds_Fuzz(uint8 _numRounds, uint8 _numPerRound) public {
        uint256 numRounds = _numRounds;
        uint256 numPerRound = _numPerRound;

        vm.assume(numRounds < 20);
        vm.assume(numPerRound < 20);

        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        uint256 numTransferredSoFar;
        for (uint256 i = 0; i < numRounds; i++) {
            // step 1.i - transfer some entries
            _entryIDs =
                rewardEscrowV1.getAccountVestingEntryIDs(user1, numTransferredSoFar, numPerRound);
            vm.prank(user1);
            escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
            numTransferredSoFar += _entryIDs.length;
        }

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, numTransferredSoFar);
        checkStateAfterStepOne(user1, _entryIDs, numRounds > 0);
    }

    /*//////////////////////////////////////////////////////////////
                           STEP 1 EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Register_Someone_Elses_Entry() public {
        // check initial state
        getStakingRewardsV1(user2);
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1
        vm.prank(user2);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        checkStateAfterStepOne(user1, _entryIDs, false);
        checkStateAfterStepOne(user2, _entryIDs, true);
    }

    function test_Cannot_Register_If_No_Escrow_Balance() public {
        // check initial state
        uint256 numVestingEntries = rewardEscrowV1.numVestingEntries(user3);
        uint256[] memory _entryIDs =
            rewardEscrowV1.getAccountVestingEntryIDs(user3, 0, numVestingEntries);
        uint256 v2BalanceBefore = rewardEscrowV2.escrowedBalanceOf(user3);
        uint256 v1BalanceBefore = rewardEscrowV1.balanceOf(user3);
        assertEq(numVestingEntries, 0);
        assertEq(v1BalanceBefore, 0);
        assertEq(v2BalanceBefore, 0);

        // step 1
        vm.prank(user3);
        vm.expectRevert(IEscrowMigrator.NoEscrowBalanceToMigrate.selector);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
    }

    function test_Cannot_Register_Without_Claiming_First() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1
        vm.prank(user2);
        vm.expectRevert(IEscrowMigrator.MustClaimStakingRewards.selector);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
    }

    function test_Cannot_Register_Vested_Entries() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // vest 10 entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        vm.prank(user1);
        rewardEscrowV1.vest(_entryIDs);

        // step 1
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 17);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 10, 7);
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Cannot_Register_Mature_Entries() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // fast forward until all entries are mature
        vm.warp(block.timestamp + 52 weeks);

        // step 1
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Cannot_Duplicate_Register_Entries() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // check final state
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Cannot_Register_Entries_That_Do_Not_Exist() public {
        // check initial state
        claimAndCheckInitialState(user1);

        // step 1
        entryIDs.push(rewardEscrowV1.nextEntryId());
        entryIDs.push(rewardEscrowV1.nextEntryId() + 1);
        entryIDs.push(rewardEscrowV1.nextEntryId() + 2);
        entryIDs.push(rewardEscrowV1.nextEntryId() + 3);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(entryIDs);

        // check final state
        uint256[] memory _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Cannot_Register_After_Confirmation() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
        // vest
        vm.prank(user1);
        rewardEscrowV1.vest(_entryIDs);
        // confirm
        vm.prank(user1);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);
        // cannot do step1 again
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInitiatedOrRegistered.selector);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                              STEP 2 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Step_2_Normal() public {
        // complete step 1 and vest
        (uint256[] memory _entryIDs,) = registerAndVestAllEntries(user1);

        // step 2.2 - confirm vest
        vm.prank(user1);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);

        // check final state
        checkStateAfterStepTwo(user1, _entryIDs, true);
    }

    function test_Step_2_Two_Rounds() public {
        // complete step 1 and vest
        (uint256[] memory _entryIDs, uint256 numVestingEntries) = registerAndVestAllEntries(user1);

        // step 2.2A - confirm vest some entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        vm.prank(user1);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);

        // step 2.2B - confirm vest more entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 10, 7);
        vm.prank(user1);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, numVestingEntries);
        checkStateAfterStepTwo(user1, _entryIDs, true);
    }

    function test_Step_2_N_Rounds_Fuzz(uint8 _numRounds, uint8 _numPerRound) public {
        uint256 numRounds = _numRounds;
        uint256 numPerRound = _numPerRound;

        vm.assume(numRounds < 20);
        vm.assume(numPerRound < 20);

        // complete step 1 and vest
        (uint256[] memory _entryIDs, uint256 numVestingEntries) = registerAndVestAllEntries(user1);

        uint256 numConfirmedSoFar;
        for (uint256 i = 0; i < numRounds; i++) {
            // step 1.i - confirm some entries
            if (numConfirmedSoFar == numVestingEntries) {
                break;
            }
            _entryIDs =
                rewardEscrowV1.getAccountVestingEntryIDs(user1, numConfirmedSoFar, numPerRound);
            vm.prank(user1);
            escrowMigrator.confirmEntriesAreVested(_entryIDs);
            numConfirmedSoFar += _entryIDs.length;
        }

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, numConfirmedSoFar);
        checkStateAfterStepTwo(user1, _entryIDs, numConfirmedSoFar == numVestingEntries);
    }

    /*//////////////////////////////////////////////////////////////
                           STEP 2 EDGE CASES
    //////////////////////////////////////////////////////////////*/

    // function test_Cannot_Confirm_On_Behalf_Of_Someone_Else() public {
    //     // check initial state
    //     (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

    //     // step 1
    //     vm.prank(user1);
    //     escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

    //     // step 2.1 - vest
    //     vm.prank(user1);
    //     rewardEscrowV1.vest(_entryIDs);

    //     // step 2.2 - confirm vest
    //     vm.prank(user1);
    //     escrowMigrator.confirmEntriesAreVested(_entryIDs);

    //     // check final state
    //     checkStateAfterStepTwo(user1, _entryIDs, true);
    // }

    // function test_Cannot_Confirm_Someone_Elses_Registered_Entry() public {

    // }

    /*//////////////////////////////////////////////////////////////
                               FULL FLOW
    //////////////////////////////////////////////////////////////*/

    function test_Migrator() public {
        getStakingRewardsV1(user1);

        uint256 v2BalanceBefore = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 v1BalanceBefore = rewardEscrowV1.balanceOf(user1);
        assertEq(v1BalanceBefore, 17.246155111414632908 ether);
        assertEq(v2BalanceBefore, 0);

        uint256 numVestingEntries = rewardEscrowV1.numVestingEntries(user1);
        assertEq(numVestingEntries, 17);

        entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, numVestingEntries);
        assertEq(entryIDs.length, 17);

        (uint256 total, uint256 totalFee) = rewardEscrowV1.getVestingQuantity(user1, entryIDs);

        assertEq(total, 3.571651297256515699 ether);
        assertEq(totalFee, 13.674503814158117209 ether);

        // step 1
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(entryIDs);

        uint256 step2UserBalance = kwenta.balanceOf(user1);
        uint256 step2MigratorBalance = kwenta.balanceOf(address(escrowMigrator));

        // step 2.1 - vest
        vm.prank(user1);
        rewardEscrowV1.vest(entryIDs);

        uint256 step2UserBalanceAfterVest = kwenta.balanceOf(user1);
        uint256 step2MigratorBalanceAfterVest = kwenta.balanceOf(address(escrowMigrator));
        assertEq(step2UserBalanceAfterVest, step2UserBalance + total);
        assertEq(step2MigratorBalanceAfterVest, step2MigratorBalance + totalFee);

        // step 2.2 - confirm vest
        vm.prank(user1);
        escrowMigrator.confirmEntriesAreVested(entryIDs);

        // step 3.1 - pay for migration
        vm.prank(user1);
        kwenta.approve(address(escrowMigrator), total);

        // step 3.2 - migrate entries
        vm.prank(user1);
        escrowMigrator.migrateRegisteredEntries(user1, entryIDs);

        // check escrow sent to v2
        uint256 v2BalanceAfter = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 v1BalanceAfter = rewardEscrowV1.balanceOf(user1);
        assertEq(v2BalanceAfter, v2BalanceBefore + total + totalFee);
        assertEq(v1BalanceAfter, v1BalanceBefore - total - totalFee);

        // confirm entries have right composition
        entryIDs = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, numVestingEntries);
        (uint256 newTotal, uint256 newTotalFee) = rewardEscrowV2.getVestingQuantity(entryIDs);

        // check within 6% of target
        assertCloseTo(newTotal, total, total / 15);
        assertCloseTo(newTotalFee, totalFee, totalFee / 15);
    }
}
// TODO: Move payment measure into confirmation step
// TODO: 3. Update checkState helpers to account for expected changes in rewardEscrowV1.balanceOf
// TODO: 4. Update checkState helpers to account for expected changes in totalRegisteredEscrow and similar added new variables
// TODO: test confirming and then registering again
// TODO: test vest, confirm, vest, confirm
// TODO: test register, vest, register, vest etc.
// TODO: test not migrating all entries from end-to-end

// QUESTION: 1. Should they be forced to migrate all entries?
// QUESTION: 2. Option to simplify to O(1) time, using just balanceOf & totalVestedAccountBalance
