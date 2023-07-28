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
        registerEntries(user1, _entryIDs);

        // check final state
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Step_1_Two_Rounds() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1 - register some entries
        registerEntries(user1, 0, 10);
        registerEntries(user1, 10, 7);

        // check final state
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Step_1_Three_Rounds() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1 - register some entries
        registerEntries(user1, 0, 5);
        registerEntries(user1, 5, 5);
        registerEntries(user1, 10, 7);

        // check final state
        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Step_1_N_Rounds_Fuzz(uint8 _numRounds, uint8 _numPerRound) public {
        uint256 numRounds = _numRounds;
        uint256 numPerRound = _numPerRound;

        vm.assume(numRounds < 20);
        vm.assume(numPerRound < 20);

        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        uint256 numRegistered;
        for (uint256 i = 0; i < numRounds; i++) {
            // register some entries
            _entryIDs = registerEntries(user1, numRegistered, numPerRound);
            numRegistered += _entryIDs.length;
        }

        // check final state
        checkStateAfterStepOne(user1, 0, numRegistered, numRounds > 0);
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
        escrowMigrator.registerEntries(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        checkStateAfterStepOne(user1, _entryIDs, false);
        checkStateAfterStepOne(user2, _entryIDs, true);
    }

    function test_Cannot_Register_If_No_Escrow_Balance() public {
        // check initial state
        uint256 numVestingEntries = rewardEscrowV1.numVestingEntries(user4);
        uint256[] memory _entryIDs =
            rewardEscrowV1.getAccountVestingEntryIDs(user4, 0, numVestingEntries);
        uint256 v1BalanceBefore = rewardEscrowV1.balanceOf(user4);
        assertEq(numVestingEntries, 0);
        assertEq(v1BalanceBefore, 0);

        // step 1
        vm.prank(user4);
        vm.expectRevert(IEscrowMigrator.NoEscrowBalanceToMigrate.selector);
        escrowMigrator.registerEntries(_entryIDs);
    }

    function test_Cannot_Register_Without_Claiming_First() public {
        // check initial state
        (uint256[] memory _entryIDs,) = checkStateBeforeStepOne(user1);

        // step 1
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustClaimStakingRewards.selector);
        escrowMigrator.registerEntries(_entryIDs);
    }

    function test_Cannot_Register_Vested_Entries() public {
        // check initial state
        claimAndCheckInitialState(user1);

        // vest 10 entries
        vest(user1, 0, 10);

        // step 1
        registerEntries(user1, 0, 17);

        // check final state
        checkStateAfterStepOne(user1, 10, 7, true);
    }

    function test_Cannot_Register_Mature_Entries() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // fast forward until all entries are mature
        vm.warp(block.timestamp + 52 weeks);

        // step 1
        registerEntries(user1, _entryIDs);

        // check final state
        checkStateAfterStepOne(user1, 0, 0, true);
    }

    function test_Cannot_Duplicate_Register_Entries() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1
        registerEntries(user1, _entryIDs);
        registerEntries(user1, _entryIDs);

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
        registerEntries(user1, entryIDs);

        // check final state
        checkStateAfterStepOne(user1, 0, 0, true);
    }

    function test_Cannot_Register_Entry_After_Migration() public {
        // check initial state
        claimAndCheckInitialState(user1);

        // step 1
        registerEntries(user1, 0, 10);
        // vest
        vest(user1, 0, 10);
        // migrate
        approveAndMigrate(user1, 0, 10);

        assertEq(escrowMigrator.numberOfRegisteredEntries(user1), 10);

        // cannot register same entries and migrate them again
        registerEntries(user1, 0, 10);
        migrateEntries(user1, 0, 10);

        checkStateAfterStepTwo(user1, 0, 10);
    }

    // /*//////////////////////////////////////////////////////////////
    //                       STEP 1 STATE LIMITS
    // //////////////////////////////////////////////////////////////*/

    // function test_Cannot_Register_In_Vesting_Confirmed_State() public {
    //     // complete step 1 and vest
    //     (uint256[] memory _entryIDs,,) = registerVestAndConfirmAllEntries(user1);

    //     // To avoid NoEscrowBalanceToMigrate check (not necessary, but bulletproofs against future changes)
    //     vm.prank(treasury);
    //     kwenta.approve(address(rewardEscrowV1), 1 ether);
    //     vm.prank(treasury);
    //     rewardEscrowV1.createEscrowEntry(user1, 1 ether, 52 weeks);

    //     // attempt in VESTING_CONFIRMED state
    //     assertEq(
    //         uint256(escrowMigrator.migrationStatus(user1)),
    //         uint256(IEscrowMigrator.MigrationStatus.VESTING_CONFIRMED)
    //     );
    //     vm.prank(user1);
    //     vm.expectRevert(IEscrowMigrator.MustBeInitiatedOrRegistered.selector);
    //     escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
    // }

    // function test_Cannot_Register_In_Paid_State() public {
    //     // move to paid state
    //     (uint256[] memory _entryIDs,) = moveToPaidState(user1);

    //     assertEq(
    //         uint256(escrowMigrator.migrationStatus(user1)),
    //         uint256(IEscrowMigrator.MigrationStatus.PAID)
    //     );
    //     vm.prank(user1);
    //     vm.expectRevert(IEscrowMigrator.MustBeInitiatedOrRegistered.selector);
    //     escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
    // }

    // function test_Cannot_Register_In_Completed_State() public {
    //     // move to completed state
    //     (uint256[] memory _entryIDs,) = moveToCompletedState(user1);

    //     assertEq(
    //         uint256(escrowMigrator.migrationStatus(user1)),
    //         uint256(IEscrowMigrator.MigrationStatus.COMPLETED)
    //     );
    //     vm.prank(user1);
    //     vm.expectRevert(IEscrowMigrator.MustBeInitiatedOrRegistered.selector);
    //     escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
    // }

    // /*//////////////////////////////////////////////////////////////
    //                    CONFIRMATION STEP TESTS
    // //////////////////////////////////////////////////////////////*/

    // function test_Confirm_Step_Takes_Account_Of_Escrow_Vested_At_Start() public {
    //     uint256 vestedBalance = rewardEscrowV1.totalVestedAccountBalance(user3);
    //     assertGt(vestedBalance, 0);

    //     // complete step 1 and vest
    //     (uint256[] memory _entryIDs,) = claimRegisterAndVestAllEntries(user3);

    //     // step 2.2 - confirm vest
    //     vm.prank(user3);
    //     escrowMigrator.confirmEntriesAreVested(_entryIDs);

    //     // check final state
    //     /// @dev skip first entry as it was vested before migration, so couldn't be migrated
    //     _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user3, 1, _entryIDs.length);
    //     checkStateAfterStepTwo(user3, _entryIDs, true);
    // }

    // /*//////////////////////////////////////////////////////////////
    //                 CONFIRMATION STEP EDGE CASES
    // //////////////////////////////////////////////////////////////*/

    // function test_Cannot_Confirm_On_Behalf_Of_Someone_Else() public {
    //     // complete step 1 and vest
    //     (uint256[] memory _entryIDs,) = claimRegisterAndVestAllEntries(user1);

    //     // register user2 so he can call confirm vest
    //     claimAndRegisterAllEntries(user2);

    //     // step 2.2 - confirm vest
    //     vm.prank(user2);
    //     escrowMigrator.confirmEntriesAreVested(_entryIDs);

    //     // check final state
    //     _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
    //     checkStateAfterStepTwo(user1, _entryIDs, false);
    // }

    // function test_Cannot_Confirm_Someone_Elses_Registered_Entry() public {
    //     // complete step 1 and vest
    //     (uint256[] memory _entryIDs,) = claimRegisterAndVestAllEntries(user1);

    //     // register user2 so he can call confirm vest
    //     claimRegisterAndVestAllEntries(user2);

    //     // step 2.2 - confirm vest
    //     vm.prank(user2);
    //     escrowMigrator.confirmEntriesAreVested(_entryIDs);

    //     // check final state
    //     _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user2, 0, 0);
    //     checkStateAfterStepTwo(user2, _entryIDs, false);
    // }

    // function test_Cannot_Confirm_Non_Registered_Entry() public {
    //     // complete step 1 and vest
    //     uint256[] memory _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
    //     claimRegisterAndVestEntries(user1, _entryIDs);

    //     // step 2.2 - confirm vest
    //     _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 17);
    //     vm.prank(user1);
    //     escrowMigrator.confirmEntriesAreVested(_entryIDs);

    //     // check final state
    //     _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
    //     checkStateAfterStepTwo(user1, _entryIDs, true);
    // }

    // function test_Cannot_Confirm_Entry_Twice() public {
    //     // complete step 1 and vest
    //     (uint256[] memory _entryIDs,) = claimRegisterAndVestAllEntries(user1);

    //     // step 2.2 - confirm vest
    //     _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
    //     vm.prank(user1);
    //     escrowMigrator.confirmEntriesAreVested(_entryIDs);
    //     _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 17);
    //     vm.prank(user1);
    //     escrowMigrator.confirmEntriesAreVested(_entryIDs);

    //     // check final state
    //     checkStateAfterStepTwo(user1, _entryIDs, true);
    // }

    // function test_Cannot_Confirm_Non_Vested_Entry() public {
    //     // complete step 1 and vest
    //     (uint256[] memory _entryIDs,) = claimAndRegisterAllEntries(user1);

    //     // step 2.2 - vest just the first handful of the entries
    //     _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
    //     vm.prank(user1);
    //     rewardEscrowV1.vest(_entryIDs);
    //     // confirm all the entries
    //     _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 17);
    //     vm.prank(user1);
    //     escrowMigrator.confirmEntriesAreVested(_entryIDs);

    //     // check final state
    //     _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
    //     checkStateAfterStepTwo(user1, _entryIDs, false);
    // }

    /*//////////////////////////////////////////////////////////////
                              STEP 2 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Step_2_Normal() public {
        // complete step 1
        (uint256[] memory _entryIDs,,) = claimRegisterVestAndApprove(user1);

        // step 2 - migrate entries
        migrateEntries(user1, _entryIDs);

        // check final state
        checkStateAfterStepTwo(user1, _entryIDs);
    }

    function test_Step_3_Two_Rounds() public {
        // complete step 1
        claimRegisterVestAndApprove(user1);

        // step 2 - migrate entries
        migrateEntries(user1, 0, 10);
        migrateEntries(user1, 10, 7);

        // check final state
        checkStateAfterStepTwo(user1, 0, 17);
    }

    function test_Step_2_N_Rounds_Fuzz(uint8 _numRounds, uint8 _numPerRound) public {
        uint256 numRounds = _numRounds;
        uint256 numPerRound = _numPerRound;

        vm.assume(numRounds < 20);
        vm.assume(numPerRound < 20);

        (uint256[] memory _entryIDs, uint256 numVestingEntries,) =
            claimRegisterVestAndApprove(user1);

        uint256 numMigrated;
        for (uint256 i = 0; i < numRounds; i++) {
            // step 2 - migrate some entries
            if (numMigrated == numVestingEntries) {
                break;
            }
            _entryIDs = migrateEntries(user1, numMigrated, numPerRound);
            numMigrated += _entryIDs.length;
        }

        // check final state
        checkStateAfterStepTwo(user1, 0, numMigrated);
    }

    /*//////////////////////////////////////////////////////////////
                           STEP 2 EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_Step_2_Must_Pay() public {
        // complete step 1
        (uint256[] memory _entryIDs,) = claimRegisterAndVestAllEntries(user1);

        // step 3.2 - migrate entries
        vm.prank(user1);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        escrowMigrator.migrateEntries(user1, _entryIDs);
    }

    function test_Step_2_Must_Pay_Fuzz(uint256 approveAmount) public {
        // complete step 1 and 2
        (uint256[] memory _entryIDs, uint256 toPay) = claimRegisterAndVestAllEntries(user1);

        vm.prank(user1);
        kwenta.approve(address(escrowMigrator), approveAmount);

        // step 2 - migrate entries
        vm.prank(user1);
        if (toPay > approveAmount) {
            vm.expectRevert("ERC20: transfer amount exceeds allowance");
        }
        escrowMigrator.migrateEntries(user1, _entryIDs);
    }

    function test_Cannot_Migrate_Non_Registered_Entries() public {
        // complete step 1
        claimRegisterVestAndApprove(user1, 0, 10);

        // step 2 - migrate extra entries
        migrateEntries(user1, 0, 17);

        // check final state
        checkStateAfterStepTwo(user1, 0, 10);
    }

    function test_Cannot_Migrate_Non_Registered_Late_Vested_Entries() public {
        // complete step 1
        claimRegisterAndVestEntries(user1, 0, 10);

        // vest extra entries and approve
        vestAndApprove(user1, 0, 17);

        // step 2 - migrate extra entries
        migrateEntries(user1, 0, 17);

        // check final state
        checkStateAfterStepTwo(user1, 0, 10);
    }

    function test_Cannot_Duplicate_Migrate_Entries() public {
        // complete step 1
        claimRegisterVestAndApprove(user1);

        // pay extra to the escrow migrator, so it would have enough money to create the extra entries
        vm.prank(treasury);
        kwenta.transfer(address(escrowMigrator), 20 ether);

        // step 2 - migrate some entries
        migrateEntries(user1, 0, 15);
        // duplicate migrate
        migrateEntries(user1, 0, 15);

        // check final state
        checkStateAfterStepTwo(user1, 0, 15);
    }

    function test_Cannot_Migrate_Non_Existing_Entries() public {
        // complete step 1
        (entryIDs,,) = claimRegisterVestAndApprove(user1);

        // step 2 - migrate entries
        entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        entryIDs.push(rewardEscrowV1.nextEntryId());
        entryIDs.push(rewardEscrowV1.nextEntryId());
        entryIDs.push(rewardEscrowV1.nextEntryId());
        entryIDs.push(rewardEscrowV1.nextEntryId());
        migrateEntries(user1, entryIDs);

        // check final state
        checkStateAfterStepTwo(user1, 0, 0);
    }

    function test_Cannot_Migrate_Someone_Elses_Entries() public {
        // complete step 1
        (uint256[] memory user1EntryIDs,,) = claimRegisterVestAndApprove(user1);
        claimRegisterVestAndApprove(user2);

        // step 2 - user2 attempts to migrate user1's entries
        migrateEntries(user2, user1EntryIDs);

        // check final state - user2 didn't manage to migrate any entries
        checkStateAfterStepTwo(user2, 0, 0);
    }

    function test_Cannot_Migrate_On_Behalf_Of_Someone() public {
        // complete step 1
        (uint256[] memory user1EntryIDs,,) = claimRegisterVestAndApprove(user1);
        claimRegisterVestAndApprove(user2);

        // step 2 - user2 attempts to migrate user1's entries
        vm.prank(user2);
        escrowMigrator.migrateEntries(user1, user1EntryIDs);

        // check final state - user2 didn't manage to migrate any entries
        checkStateAfterStepTwo(user1, 0, 0);
    }

    function test_Cannot_Bypass_Unstaking_Cooldown_Lock() public {
        // this is the malicious entry - the duration is set to 1
        createRewardEscrowEntryV1(user1, 50 ether, 1);

        (uint256[] memory _entryIDs, uint256 numVestingEntries,) = fullyMigrateAllEntries(user1);
        checkStateAfterStepTwo(user1, _entryIDs);

        // specifically
        uint256[] memory migratedEntryIDs =
            rewardEscrowV2.getAccountVestingEntryIDs(user1, numVestingEntries - 2, 1);
        uint256 maliciousEntryID = migratedEntryIDs[0];
        (uint64 endTime, uint256 escrowAmount, uint256 duration, uint8 earlyVestingFee) =
            rewardEscrowV2.getVestingEntry(maliciousEntryID);
        assertEq(endTime, block.timestamp + stakingRewardsV2.cooldownPeriod());
        assertEq(escrowAmount, 50 ether);
        assertEq(duration, stakingRewardsV2.cooldownPeriod());
        assertEq(earlyVestingFee, 90);
    }

    function test_Cannot_Migrate_In_Non_Initiated_State() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // attempt in non initiated state
        assertEq(escrowMigrator.initiated(user1), false);

        // step 2 - migrate entries
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInitiated.selector);
        escrowMigrator.migrateEntries(user1, _entryIDs);
    }

    // /*//////////////////////////////////////////////////////////////
    //                       STEP 3 STATE LIMITS
    // //////////////////////////////////////////////////////////////*/

    // function test_Cannot_Migrate_In_Not_Started_State() public {
    //     // complete step 1 and 2
    //     uint256[] memory _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(
    //         user1, 0, rewardEscrowV1.numVestingEntries(user1)
    //     );
    //     assertEq(
    //         uint256(escrowMigrator.migrationStatus(user1)),
    //         uint256(IEscrowMigrator.MigrationStatus.NOT_STARTED)
    //     );

    //     // step 3.1 - migrate entries
    //     vm.prank(user1);
    //     vm.expectRevert(IEscrowMigrator.MustBeInVestingConfirmedState.selector);
    //     escrowMigrator.migrateEntries(user1, _entryIDs);
    // }

    // function test_Cannot_Migrate_In_Initiated_State() public {
    //     (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

    //     // attempt in INITIATED state
    //     _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
    //     vm.prank(user1);
    //     escrowMigrator.registerEntries(_entryIDs);
    //     assertEq(
    //         uint256(escrowMigrator.migrationStatus(user1)),
    //         uint256(IEscrowMigrator.MigrationStatus.INITIATED)
    //     );

    //     // step 3.1 - migrate entries
    //     vm.prank(user1);
    //     vm.expectRevert(IEscrowMigrator.MustBeInVestingConfirmedState.selector);
    //     escrowMigrator.migrateEntries(user1, _entryIDs);
    // }

    // function test_Cannot_Migrate_In_Registered_State() public {
    //     // complete step 1 and 2
    //     (uint256[] memory _entryIDs,) = claimAndRegisterAllEntries(user1);
    //     assertEq(
    //         uint256(escrowMigrator.migrationStatus(user1)),
    //         uint256(IEscrowMigrator.MigrationStatus.REGISTERED)
    //     );

    //     // step 3.1 - migrate entries
    //     vm.prank(user1);
    //     vm.expectRevert(IEscrowMigrator.MustBeInVestingConfirmedState.selector);
    //     escrowMigrator.migrateEntries(user1, _entryIDs);
    // }

    // function test_Cannot_Migrate_In_Completed_State() public {
    //     // move to completed state
    //     (uint256[] memory _entryIDs,) = moveToCompletedState(user1);

    //     assertEq(
    //         uint256(escrowMigrator.migrationStatus(user1)),
    //         uint256(IEscrowMigrator.MigrationStatus.COMPLETED)
    //     );
    //     vm.prank(user1);
    //     vm.expectRevert(IEscrowMigrator.MustBeInPaidState.selector);
    //     escrowMigrator.migrateEntries(user1, _entryIDs);
    // }

    // // TODO: can migrate, then register more entries?
    // // TODO: test sending entries to another `to` address

    // /*//////////////////////////////////////////////////////////////
    //                            FULL FLOW
    // //////////////////////////////////////////////////////////////*/

    // function test_Migrator() public {
    //     getStakingRewardsV1(user1);

    //     uint256 v2BalanceBefore = rewardEscrowV2.escrowedBalanceOf(user1);
    //     uint256 v1BalanceBefore = rewardEscrowV1.balanceOf(user1);
    //     assertEq(v1BalanceBefore, 17.246155111414632908 ether);
    //     assertEq(v2BalanceBefore, 0);

    //     uint256 numVestingEntries = rewardEscrowV1.numVestingEntries(user1);
    //     assertEq(numVestingEntries, 17);

    //     entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, numVestingEntries);
    //     assertEq(entryIDs.length, 17);

    //     (uint256 total, uint256 totalFee) = rewardEscrowV1.getVestingQuantity(user1, entryIDs);

    //     assertEq(total, 3.819707122432513665 ether);
    //     assertEq(totalFee, 13.426447988982119243 ether);

    //     // step 1
    //     vm.prank(user1);
    //     escrowMigrator.registerEntries(entryIDs);

    //     uint256 step2UserBalance = kwenta.balanceOf(user1);
    //     uint256 step2MigratorBalance = kwenta.balanceOf(address(escrowMigrator));

    //     // step 2.1 - vest
    //     vm.prank(user1);
    //     rewardEscrowV1.vest(entryIDs);

    //     uint256 step2UserBalanceAfterVest = kwenta.balanceOf(user1);
    //     uint256 step2MigratorBalanceAfterVest = kwenta.balanceOf(address(escrowMigrator));
    //     assertEq(step2UserBalanceAfterVest, step2UserBalance + total);
    //     assertEq(step2MigratorBalanceAfterVest, step2MigratorBalance + totalFee);

    //     // step 2.2 - confirm vest
    //     vm.prank(user1);
    //     escrowMigrator.confirmEntriesAreVested(entryIDs);

    //     // step 3.1 - pay for migration
    //     vm.prank(user1);
    //     kwenta.approve(address(escrowMigrator), total);

    //     // step 3.2 - migrate entries
    //     vm.prank(user1);
    //     escrowMigrator.migrateEntries(user1, entryIDs);

    //     // check escrow sent to v2
    //     uint256 v2BalanceAfter = rewardEscrowV2.escrowedBalanceOf(user1);
    //     uint256 v1BalanceAfter = rewardEscrowV1.balanceOf(user1);
    //     assertEq(v2BalanceAfter, v2BalanceBefore + total + totalFee);
    //     assertEq(v1BalanceAfter, v1BalanceBefore - total - totalFee);

    //     // confirm entries have right composition
    //     entryIDs = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, numVestingEntries);
    //     (uint256 newTotal, uint256 newTotalFee) = rewardEscrowV2.getVestingQuantity(entryIDs);

    //     // check within 1% of target
    //     assertCloseTo(newTotal, total, total / 100);
    //     assertCloseTo(newTotalFee, totalFee, totalFee / 100);
    // }

    // /*//////////////////////////////////////////////////////////////
    //                     STRANGE EFFECTIVE FLOWS
    // //////////////////////////////////////////////////////////////*/

    // /// @dev There are numerous different ways the user could interact with the system,
    // /// as opposed for the way we intend for the user to interact with the system.
    // /// These tests check that users going "alterantive routes" don't break the system.
    // /// In order to breifly annoate special flows, I have created an annotation system:
    // /// R = register, V = vest, C = confirm, M = migrate, P = pay, N = create new escrow entry
    // /// So for example, RVC means register, vest, confirm, in that order

    // function test_RVRVC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 5);
    //     // V
    //     vest(user1, 0, 5);
    //     // R
    //     registerEntries(user1, 5, 5);
    //     // V
    //     vest(user1, 5, 5);
    //     // C
    //     confirm(user1, 0, 10);

    //     checkStateAfterStepTwo(user1, 0, 10, true);
    // }

    // function test_RVCRVC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);
    //     // V
    //     vest(user1, 0, 5);
    //     // C
    //     confirm(user1, 0, 5);
    //     // R
    //     registerEntries(user1, 6, 4);
    //     // V
    //     vest(user1, 5, 5);
    //     // C
    //     confirm(user1, 5, 5);

    //     checkStateAfterStepTwo(user1, 0, 10, true);
    // }

    // /*//////////////////////////////////////////////////////////////
    //                    STRANGE FLOWS UP TO STEP 1
    // //////////////////////////////////////////////////////////////*/

    // function test_NR() public {
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);

    //     checkStateAfterStepOne(user1, 0, 6, true);
    // }

    // function test_VR() public {
    //     // V
    //     vest(user1, 0, 3);
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);

    //     checkStateAfterStepOne(user1, 3, 3, true);
    // }

    // function test_NVR() public {
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // V
    //     vest(user1, 0, 3);
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);

    //     checkStateAfterStepOne(user1, 3, 3, true);
    // }

    // function test_VNR() public {
    //     // V
    //     vest(user1, 0, 3);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);

    //     checkStateAfterStepOne(user1, 3, 3, true);
    // }

    // /*//////////////////////////////////////////////////////////////
    //                    STRANGE FLOWS UP TO STEP 2
    // //////////////////////////////////////////////////////////////*/

    // function test_RNC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // C
    //     confirm(user1, 0, 6);

    //     checkStateAfterStepTwo(user1, 0, 0, false);
    // }

    // function test_RNVC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // V
    //     vest(user1, 0, 3);
    //     // C
    //     confirm(user1, 0, 6);

    //     checkStateAfterStepTwo(user1, 0, 3, false);
    // }

    // function test_RVNC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);
    //     // V
    //     vest(user1, 0, 3);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // C
    //     confirm(user1, 0, 6);

    //     checkStateAfterStepTwo(user1, 0, 3, false);
    // }

    // function test_RNVRVC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // V
    //     vest(user1, 0, 3);
    //     // R
    //     registerEntries(user1, 6, 4);
    //     // V
    //     vest(user1, 3, 3);
    //     // C
    //     confirm(user1, 0, 10);

    //     checkStateAfterStepTwo(user1, 0, 6, false);
    // }

    // function test_RVNRVC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);
    //     // V
    //     vest(user1, 0, 3);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // R
    //     registerEntries(user1, 6, 4);
    //     // V
    //     vest(user1, 3, 3);
    //     // C
    //     confirm(user1, 0, 10);

    //     checkStateAfterStepTwo(user1, 0, 6, false);
    // }

    // function test_RVRNVC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);
    //     // V
    //     vest(user1, 0, 3);
    //     // R
    //     registerEntries(user1, 6, 4);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // V
    //     vest(user1, 3, 3);
    //     // C
    //     confirm(user1, 0, 10);

    //     checkStateAfterStepTwo(user1, 0, 6, false);
    // }

    // function test_RVRVNC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);
    //     // V
    //     vest(user1, 0, 3);
    //     // R
    //     registerEntries(user1, 6, 4);
    //     // V
    //     vest(user1, 3, 7);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // C
    //     confirm(user1, 0, 10);

    //     checkStateAfterStepTwo(user1, 0, 10, true);
    // }

    // function test_RNVCRVC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // V
    //     vest(user1, 0, 3);
    //     // C
    //     confirm(user1, 0, 6);
    //     // R
    //     registerEntries(user1, 6, 4);
    //     // V
    //     vest(user1, 3, 7);
    //     // C
    //     confirm(user1, 0, 10);

    //     checkStateAfterStepTwo(user1, 0, 10, true);
    // }

    // function test_RVNCRVC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 6);
    //     // V
    //     vest(user1, 0, 3);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // C
    //     confirm(user1, 0, 6);
    //     // R
    //     registerEntries(user1, 6, 4);
    //     // V
    //     vest(user1, 3, 7);
    //     // C
    //     confirm(user1, 0, 10);

    //     checkStateAfterStepTwo(user1, 0, 10, true);
    // }

    // function test_RVCNRVC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 10);
    //     // V
    //     vest(user1, 0, 3);
    //     // C
    //     confirm(user1, 0, 6);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // R
    //     registerEntries(user1, 10, 4);
    //     // V
    //     vest(user1, 3, 7);
    //     // C
    //     confirm(user1, 0, 10);

    //     checkStateAfterStepTwo(user1, 0, 10, false);
    // }

    // function test_RVCRNVC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 10);
    //     // V
    //     vest(user1, 0, 3);
    //     // C
    //     confirm(user1, 0, 6);
    //     // R
    //     registerEntries(user1, 10, 7);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // V
    //     vest(user1, 3, 14);
    //     // C
    //     confirm(user1, 3, 17);

    //     checkStateAfterStepTwo(user1, 0, 17, true);
    // }

    // function test_RVCRVNC() public {
    //     // R
    //     claimAndRegisterEntries(user1, 0, 10);
    //     // V
    //     vest(user1, 0, 3);
    //     // C
    //     confirm(user1, 0, 6);
    //     // R
    //     registerEntries(user1, 10, 7);
    //     // V
    //     vest(user1, 3, 14);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // C
    //     confirm(user1, 3, 17);

    //     checkStateAfterStepTwo(user1, 0, 17, true);
    // }

    // /*//////////////////////////////////////////////////////////////
    //                    STRANGE FLOWS UP TO STEP 3
    // //////////////////////////////////////////////////////////////*/

    // function test_CVM() public {
    //     claimRegisterAndVestEntries(user1, 0, 10);

    //     // C
    //     confirm(user1, 0, 10);
    //     // V
    //     vest(user1, 0, 17);
    //     // M
    //     approveAndMigrate(user1, 0, 10);

    //     checkStateAfterStepTwo(user1, 0, 10, true);
    // }

    // function test_CNM() public {
    //     claimRegisterAndVestEntries(user1, 0, 17);

    //     // C
    //     confirm(user1, 0, 17);
    //     // N
    //     createRewardEscrowEntryV1(user1, 1 ether);
    //     // M
    //     approveAndMigrate(user1, 0, 17);

    //     checkStateAfterStepTwo(user1, 0, 17, true);
    // }
}

// Up to step 3

// CNVM
// CVNM

// TODO: 3. Update checkState helpers to account for expected changes in rewardEscrowV1.balanceOf
// TODO: 4. Update checkState helpers to account for expected changes in totalRegisteredEscrow and similar added new variables
// TODO: test confirming and then registering again
// TODO: test vest, confirm, vest, confirm
// TODO: test register, vest, register, vest etc.
// TODO: test confirm, register, vest, confirm
// TODO: test not migrating all entries from end-to-end
// TODO: add tests to ensure each function can only be executed in the correct state for step 1 & 3
// TODO: test sending in entryIDs in a funny order

// QUESTION: 2. Option to simplify to O(1) time, using just balanceOf & totalVestedAccountBalance
