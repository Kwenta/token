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
        (uint256[] memory _entryIDs,) =
            checkStateBeforeStepOne(user1, 16.324711673459301166 ether, 16);

        // step 1
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // check final state
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Step_1_Two_Rounds() public {
        // check initial state
        (uint256[] memory _entryIDs, uint256 numVestingEntries) =
            checkStateBeforeStepOne(user1, 16.324711673459301166 ether, 16);

        // step 1.1 - transfer some entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // step 1.2 - transfer some more entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 10, 6);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, numVestingEntries);
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Step_1_Three_Rounds() public {
        // check initial state
        (uint256[] memory _entryIDs, uint256 numVestingEntries) =
            checkStateBeforeStepOne(user1, 16.324711673459301166 ether, 16);

        // step 1.1 - transfer some entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 5);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // step 1.2 - transfer some more entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 5, 5);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // step 1.3 - transfer some more entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 10, 6);
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
        (uint256[] memory _entryIDs,) =
            checkStateBeforeStepOne(user1, 16.324711673459301166 ether, 16);

        uint256 numTransferredSoFar;
        for (uint256 i = 0; i < numRounds; i++) {
            // step 1.i - transfer some entries
            _entryIDs =
                rewardEscrowV1.getAccountVestingEntryIDs(user1, numTransferredSoFar, numPerRound);
            vm.prank(user1);
            escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
            numTransferredSoFar += numPerRound;
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
        (uint256[] memory _entryIDs,) =
            checkStateBeforeStepOne(user1, 16.324711673459301166 ether, 16);

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
        (uint256[] memory _entryIDs,) = checkStateBeforeStepOne(user3, 0, 0);

        // step 1
        vm.prank(user3);
        vm.expectRevert(IEscrowMigrator.NoEscrowBalanceToMigrate.selector);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
    }

    function test_Cannot_Register_Vested_Entries() public {
        // check initial state
        (uint256[] memory _entryIDs,) =
            checkStateBeforeStepOne(user1, 16.324711673459301166 ether, 16);

        // vest 15 entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        vm.prank(user1);
        rewardEscrowV1.vest(_entryIDs);

        // step 1
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 10, 6);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // check final state
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Cannot_Register_Mature_Entries() public {
        // check initial state
        (uint256[] memory _entryIDs,) =
            checkStateBeforeStepOne(user1, 16.324711673459301166 ether, 16);

        // fast forward until all entries are mature
        vm.warp(block.timestamp + 52 weeks);

        // step 1
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Cannot_Register_Entries_That_Do_Not_Exist() public {
        // check initial state
        checkStateBeforeStepOne(user1, 16.324711673459301166 ether, 16);

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
        (uint256[] memory _entryIDs,) =
            checkStateBeforeStepOne(user1, 16.324711673459301166 ether, 16);

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
        // check initial state
        (uint256[] memory _entryIDs,) =
            checkStateBeforeStepOne(user1, 16.324711673459301166 ether, 16);

        // step 1
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);

        // step 2.1 - vest
        vm.prank(user1);
        rewardEscrowV1.vest(_entryIDs);

        // step 2.2 - confirm vest
        vm.prank(user1);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);

        // check final state
        checkStateAfterStepTwo(user1, _entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                               FULL FLOW
    //////////////////////////////////////////////////////////////*/

    function test_Migrator() public {
        uint256 v2BalanceBefore = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 v1BalanceBefore = rewardEscrowV1.balanceOf(user1);
        assertEq(v1BalanceBefore, 16.324711673459301166 ether);
        assertEq(v2BalanceBefore, 0);

        uint256 numVestingEntries = rewardEscrowV1.numVestingEntries(user1);
        assertEq(numVestingEntries, 16);

        entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, numVestingEntries);
        assertEq(entryIDs.length, 16);

        (uint256 total, uint256 totalFee) = rewardEscrowV1.getVestingQuantity(user1, entryIDs);

        assertEq(total, 3_479_506_953_460_982_524);
        assertEq(totalFee, 12_845_204_719_998_318_642);

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

// TODO: 1. check no earning on stakingv1 before initiating
// TODO: 2. check rewardEscrowV1.balanceOf changes by correct amount between registration and confirmation
// TODO: 3. Update checkState helpers to account for expected changes in rewardEscrowV1.balanceOf
// TODO: 4. Update checkState helpers to account for expected changes in totalRegisteredEscrow and similar added new variables

// QUESTION: 1. Should they be forced to migrate all entries?
