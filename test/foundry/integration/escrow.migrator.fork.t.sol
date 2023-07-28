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
        uint256 numVestingEntries = rewardEscrowV1.numVestingEntries(user4);
        uint256[] memory _entryIDs =
            rewardEscrowV1.getAccountVestingEntryIDs(user4, 0, numVestingEntries);
        uint256 v2BalanceBefore = rewardEscrowV2.escrowedBalanceOf(user4);
        uint256 v1BalanceBefore = rewardEscrowV1.balanceOf(user4);
        assertEq(numVestingEntries, 0);
        assertEq(v1BalanceBefore, 0);
        assertEq(v2BalanceBefore, 0);

        // step 1
        vm.prank(user4);
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
                          STEP 1 STATE LIMITS
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Register_In_Vesting_Confirmed_State() public {
        // complete step 1 and vest
        (uint256[] memory _entryIDs,,) = registerVestAndConfirmAllEntries(user1);

        // To avoid NoEscrowBalanceToMigrate check (not necessary, but bulletproofs against future changes)
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV1), 1 ether);
        vm.prank(treasury);
        rewardEscrowV1.createEscrowEntry(user1, 1 ether, 52 weeks);

        // attempt in VESTING_CONFIRMED state
        assertEq(
            uint256(escrowMigrator.migrationStatus(user1)),
            uint256(IEscrowMigrator.MigrationStatus.VESTING_CONFIRMED)
        );
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInitiatedOrRegistered.selector);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
    }

    function test_Cannot_Register_In_Paid_State() public {
        // move to paid state
        (uint256[] memory _entryIDs,) = moveToPaidState(user1);

        assertEq(
            uint256(escrowMigrator.migrationStatus(user1)),
            uint256(IEscrowMigrator.MigrationStatus.PAID)
        );
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInitiatedOrRegistered.selector);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
    }

    function test_Cannot_Register_In_Completed_State() public {
        // move to completed state
        (uint256[] memory _entryIDs,) = moveToCompletedState(user1);

        assertEq(
            uint256(escrowMigrator.migrationStatus(user1)),
            uint256(IEscrowMigrator.MigrationStatus.COMPLETED)
        );
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
            // step 2.i - confirm some entries
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

    function test_Confirm_Step_Takes_Account_Of_Escrow_Vested_At_Start() public {
        uint256 vestedBalance = rewardEscrowV1.totalVestedAccountBalance(user3);
        assertGt(vestedBalance, 0);

        // complete step 1 and vest
        (uint256[] memory _entryIDs,) = registerAndVestAllEntries(user3);

        // step 2.2 - confirm vest
        vm.prank(user3);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);

        // check final state
        /// @dev skip first entry as it was vested before migration, so couldn't be migrated
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user3, 1, _entryIDs.length);
        checkStateAfterStepTwo(user3, _entryIDs, true);
    }

    /*//////////////////////////////////////////////////////////////
                          STEP 2 STATE LIMITS
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Confirm_In_Not_Started_State() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // attempt in NOT_STARTED state
        assertEq(
            uint256(escrowMigrator.migrationStatus(user1)),
            uint256(IEscrowMigrator.MigrationStatus.NOT_STARTED)
        );
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInRegisteredState.selector);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);
    }

    function test_Cannot_Confirm_In_Initiated_State() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // attempt in INITIATED state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
        assertEq(
            uint256(escrowMigrator.migrationStatus(user1)),
            uint256(IEscrowMigrator.MigrationStatus.INITIATED)
        );
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInRegisteredState.selector);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);
    }

    function test_Cannot_Confirm_In_Vesting_Confirmed_State() public {
        // complete step 1 and vest
        (uint256[] memory _entryIDs,,) = registerVestAndConfirmAllEntries(user1);

        // attempt in VESTING_CONFIRMED state
        assertEq(
            uint256(escrowMigrator.migrationStatus(user1)),
            uint256(IEscrowMigrator.MigrationStatus.VESTING_CONFIRMED)
        );
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInRegisteredState.selector);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);
    }

    function test_Cannot_Confirm_In_Paid_State() public {
        // move to paid state
        (uint256[] memory _entryIDs,) = moveToPaidState(user1);

        assertEq(
            uint256(escrowMigrator.migrationStatus(user1)),
            uint256(IEscrowMigrator.MigrationStatus.PAID)
        );
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInRegisteredState.selector);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);
    }

    function test_Cannot_Confirm_In_Completed_State() public {
        // move to completed state
        (uint256[] memory _entryIDs,) = moveToCompletedState(user1);

        assertEq(
            uint256(escrowMigrator.migrationStatus(user1)),
            uint256(IEscrowMigrator.MigrationStatus.COMPLETED)
        );
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInRegisteredState.selector);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                           STEP 2 EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Confirm_On_Behalf_Of_Someone_Else() public {
        // complete step 1 and vest
        (uint256[] memory _entryIDs,) = registerAndVestAllEntries(user1);

        // register user2 so he can call confirm vest
        registerAllEntries(user2);

        // step 2.2 - confirm vest
        vm.prank(user2);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        checkStateAfterStepTwo(user1, _entryIDs, false);
    }

    function test_Cannot_Confirm_Someone_Elses_Registered_Entry() public {
        // complete step 1 and vest
        (uint256[] memory _entryIDs,) = registerAndVestAllEntries(user1);

        // register user2 so he can call confirm vest
        registerAndVestAllEntries(user2);

        // step 2.2 - confirm vest
        vm.prank(user2);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user2, 0, 0);
        checkStateAfterStepTwo(user2, _entryIDs, false);
    }

    function test_Cannot_Confirm_Non_Registered_Entry() public {
        // complete step 1 and vest
        uint256[] memory _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        registerAndVestEntries(user1, _entryIDs);

        // step 2.2 - confirm vest
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 17);
        vm.prank(user1);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        checkStateAfterStepTwo(user1, _entryIDs, true);
    }

    function test_Cannot_Confirm_Entry_Twice() public {
        // complete step 1 and vest
        (uint256[] memory _entryIDs,) = registerAndVestAllEntries(user1);

        // step 2.2 - confirm vest
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        vm.prank(user1);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 17);
        vm.prank(user1);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);

        // check final state
        checkStateAfterStepTwo(user1, _entryIDs, true);
    }

    function test_Cannot_Confirm_Non_Vested_Entry() public {
        // complete step 1 and vest
        (uint256[] memory _entryIDs,) = registerAllEntries(user1);

        // step 2.2 - vest just the first handful of the entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        vm.prank(user1);
        rewardEscrowV1.vest(_entryIDs);
        // confirm all the entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 17);
        vm.prank(user1);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        checkStateAfterStepTwo(user1, _entryIDs, false);
    }

    /*//////////////////////////////////////////////////////////////
                              STEP 3 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Step_3_Normal() public {
        // complete step 1 and 2
        (uint256[] memory _entryIDs,,) = registerVestConfirmAllEntriesAndApprove(user1);

        // step 3.2 - migrate entries
        vm.prank(user1);
        escrowMigrator.migrateConfirmedEntries(user1, _entryIDs);

        // check final state
        checkStateAfterStepThree(user1, _entryIDs, true);
    }

    function test_Step_3_Two_Rounds() public {
        // complete step 1 and 2
        (uint256[] memory _entryIDs,,) = registerVestConfirmAllEntriesAndApprove(user1);

        // step 3.2 - migrate some entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        vm.prank(user1);
        escrowMigrator.migrateConfirmedEntries(user1, _entryIDs);

        // step 3.2 - migrate some more entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 10, 7);
        vm.prank(user1);
        escrowMigrator.migrateConfirmedEntries(user1, _entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 17);
        checkStateAfterStepThree(user1, _entryIDs, true);
    }

    function test_Step_3_N_Rounds_Fuzz(uint8 _numRounds, uint8 _numPerRound) public {
        uint256 numRounds = _numRounds;
        uint256 numPerRound = _numPerRound;

        vm.assume(numRounds < 20);
        vm.assume(numPerRound < 20);

        (uint256[] memory _entryIDs, uint256 numVestingEntries,) =
            registerVestConfirmAllEntriesAndApprove(user1);

        uint256 numConfirmedSoFar;
        for (uint256 i = 0; i < numRounds; i++) {
            // step 3.i - migrate some entries
            if (numConfirmedSoFar == numVestingEntries) {
                break;
            }
            _entryIDs =
                rewardEscrowV1.getAccountVestingEntryIDs(user1, numConfirmedSoFar, numPerRound);
            vm.prank(user1);
            escrowMigrator.migrateConfirmedEntries(user1, _entryIDs);
            numConfirmedSoFar += _entryIDs.length;
        }

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, numConfirmedSoFar);
        checkStateAfterStepThree(user1, _entryIDs, numRounds > 0);
    }

    /*//////////////////////////////////////////////////////////////
                           STEP 3 EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_Step_3_Must_Pay() public {
        // complete step 1 and 2
        (uint256[] memory _entryIDs,,) = registerVestAndConfirmAllEntries(user1);

        // step 3.2 - migrate entries
        vm.prank(user1);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        escrowMigrator.migrateConfirmedEntries(user1, _entryIDs);
    }

    function test_Step_3_Must_Pay_Fuzz(uint256 approveAmount) public {
        // complete step 1 and 2
        (uint256[] memory _entryIDs,, uint256 toPay) = registerVestAndConfirmAllEntries(user1);

        vm.prank(user1);
        kwenta.approve(address(escrowMigrator), approveAmount);

        // step 3.2 - migrate entries
        vm.prank(user1);
        if (toPay > approveAmount) {
            vm.expectRevert("ERC20: transfer amount exceeds allowance");
        }
        escrowMigrator.migrateConfirmedEntries(user1, _entryIDs);
    }

    function test_Cannot_Migrate_Non_Registered_Entries() public {
        // complete step 1 and 2
        uint256[] memory _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        registerVestConfirmAndApproveEntries(user1, _entryIDs);

        // step 3.2 - migrate extra entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 17);
        vm.prank(user1);
        escrowMigrator.migrateConfirmedEntries(user1, _entryIDs);

        // check final state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 10);
        checkStateAfterStepThree(user1, _entryIDs, true);
    }

    function test_Cannot_Duplicate_Migrate_Entries() public {
        // complete step 1 and 2
        (uint256[] memory _entryIDs,,) = registerVestConfirmAllEntriesAndApprove(user1);

        // pay extra to the escrow migrator, so it would have enough money to create the extra entries
        vm.prank(treasury);
        kwenta.transfer(address(escrowMigrator), 20 ether);

        // step 3.2 - migrate some entries
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 15);
        vm.prank(user1);
        escrowMigrator.migrateConfirmedEntries(user1, _entryIDs);

        // step 3.2 - duplicate migrate
        vm.prank(user1);
        escrowMigrator.migrateConfirmedEntries(user1, _entryIDs);

        // check final state
        checkStateAfterStepThree(user1, _entryIDs, true);
    }

    function test_Cannot_Migrate_Non_Existing_Entries() public {
        // complete step 1 and 2
        (entryIDs,,) = registerVestConfirmAllEntriesAndApprove(user1);

        // step 3.2 - migrate entries
        entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        entryIDs.push(rewardEscrowV1.nextEntryId());
        entryIDs.push(rewardEscrowV1.nextEntryId());
        entryIDs.push(rewardEscrowV1.nextEntryId());
        entryIDs.push(rewardEscrowV1.nextEntryId());
        vm.prank(user1);
        escrowMigrator.migrateConfirmedEntries(user1, entryIDs);

        // check final state
        entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        checkStateAfterStepThree(user1, entryIDs, true);
    }

    function test_Cannot_Migrate_Someone_Elses_Entries() public {
        // complete step 1 and 2
        (uint256[] memory user1EntryIDs,,) = registerVestConfirmAllEntriesAndApprove(user1);
        registerVestConfirmAllEntriesAndApprove(user2);

        // step 3.2 - user2 attempts to migrate user1's entries
        vm.prank(user2);
        escrowMigrator.migrateConfirmedEntries(user2, user1EntryIDs);

        // check final state - user2 didn't manage to migrate any entries
        uint256[] memory migratedEntryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user2, 0, 0);
        checkStateAfterStepThree(user2, migratedEntryIDs, true);
    }

    function test_Cannot_Migrate_On_Behalf_Of_Someone() public {
        // complete step 1 and 2
        (uint256[] memory user1EntryIDs,,) = registerVestConfirmAllEntriesAndApprove(user1);
        registerVestConfirmAllEntriesAndApprove(user2);

        // step 3.2 - user2 attempts to migrate user1's entries
        vm.prank(user2);
        escrowMigrator.migrateConfirmedEntries(user1, user1EntryIDs);

        // check final state - user2 didn't manage to migrate any entries
        uint256[] memory migratedEntryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        checkStateAfterStepThree(user1, migratedEntryIDs, false);
    }

    function test_Cannot_Bypass_Unstaking_Cooldown_Lock() public {
        vm.prank(treasury);
        kwenta.transfer(user1, 50 ether);
        vm.prank(user1);
        kwenta.approve(address(rewardEscrowV1), type(uint256).max);
        vm.prank(user1);
        // this is the malicious entry - the duration is set to 1
        rewardEscrowV1.createEscrowEntry(user1, 50 ether, 1);

        (uint256[] memory _entryIDs, uint256 numVestingEntries,) = fullyMigrateAllEntries(user1);
        checkStateAfterStepThree(user1, _entryIDs, true);

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

    /*//////////////////////////////////////////////////////////////
                          STEP 3 STATE LIMITS
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Migrate_In_Not_Started_State() public {
        // complete step 1 and 2
        uint256[] memory _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(
            user1, 0, rewardEscrowV1.numVestingEntries(user1)
        );
        assertEq(
            uint256(escrowMigrator.migrationStatus(user1)),
            uint256(IEscrowMigrator.MigrationStatus.NOT_STARTED)
        );

        // step 3.1 - migrate entries
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInVestingConfirmedState.selector);
        escrowMigrator.migrateConfirmedEntries(user1, _entryIDs);
    }

    function test_Cannot_Migrate_In_Initiated_State() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // attempt in INITIATED state
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, 0);
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
        assertEq(
            uint256(escrowMigrator.migrationStatus(user1)),
            uint256(IEscrowMigrator.MigrationStatus.INITIATED)
        );

        // step 3.1 - migrate entries
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInVestingConfirmedState.selector);
        escrowMigrator.migrateConfirmedEntries(user1, _entryIDs);
    }

    function test_Cannot_Migrate_In_Registered_State() public {
        // complete step 1 and 2
        (uint256[] memory _entryIDs,) = registerAllEntries(user1);
        assertEq(
            uint256(escrowMigrator.migrationStatus(user1)),
            uint256(IEscrowMigrator.MigrationStatus.REGISTERED)
        );

        // step 3.1 - migrate entries
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInVestingConfirmedState.selector);
        escrowMigrator.migrateConfirmedEntries(user1, _entryIDs);
    }

    function test_Cannot_Migrate_In_Completed_State() public {
        // move to completed state
        (uint256[] memory _entryIDs,) = moveToCompletedState(user1);

        assertEq(
            uint256(escrowMigrator.migrationStatus(user1)),
            uint256(IEscrowMigrator.MigrationStatus.COMPLETED)
        );
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInPaidState.selector);
        escrowMigrator.migrateConfirmedEntries(user1, _entryIDs);
    }

    // TODO: can migrate, then register more entries?
    // TODO: test sending entries to another `to` address

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

        assertEq(total, 3.819707122432513665 ether);
        assertEq(totalFee, 13.426447988982119243 ether);

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
        escrowMigrator.migrateConfirmedEntries(user1, entryIDs);

        // check escrow sent to v2
        uint256 v2BalanceAfter = rewardEscrowV2.escrowedBalanceOf(user1);
        uint256 v1BalanceAfter = rewardEscrowV1.balanceOf(user1);
        assertEq(v2BalanceAfter, v2BalanceBefore + total + totalFee);
        assertEq(v1BalanceAfter, v1BalanceBefore - total - totalFee);

        // confirm entries have right composition
        entryIDs = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, numVestingEntries);
        (uint256 newTotal, uint256 newTotalFee) = rewardEscrowV2.getVestingQuantity(entryIDs);

        // check within 1% of target
        assertCloseTo(newTotal, total, total / 100);
        assertCloseTo(newTotalFee, totalFee, totalFee / 100);
    }

    /*//////////////////////////////////////////////////////////////
                        STRANGE EFFECTIVE FLOWS
    //////////////////////////////////////////////////////////////*/

    /// @dev There are numerous different ways the user could interact with the system,
    /// as opposed for the way we intend for the user to interact with the system.
    /// These tests check that users going "alterantive routes" don't break the system.
    /// In order to breifly annoate special flows, I have created an annotation system:
    /// R = register, V = vest, C = confirm, M = migrate, P = pay, N = create new escrow entry
    /// So for example, RVC means register, vest, confirm, in that order

    function test_RVRVC() public {
        // R
        claimAndRegisterEntries(user1, 0, 5);
        // V
        vest(user1, 0, 5);
        // R
        registerEntries(user1, 5, 5);
        // V
        vest(user1, 5, 5);
        // C
        confirm(user1, 0, 10);

        checkStateAfterStepTwo(user1, 0, 10, true);
    }

    function test_RVCRVC() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 5);
        // C
        confirm(user1, 0, 5);
        // R
        registerEntries(user1, 6, 4);
        // V
        vest(user1, 5, 5);
        // C
        confirm(user1, 5, 5);

        checkStateAfterStepTwo(user1, 0, 10, true);
    }

    /*//////////////////////////////////////////////////////////////
                       STRANGE FLOWS UP TO STEP 1
    //////////////////////////////////////////////////////////////*/

    function test_NR() public {
        // N
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        claimAndRegisterEntries(user1, 0, 6);

        checkStateAfterStepOne(user1, 0, 6, true);
    }

    function test_VR() public {
        // V
        vest(user1, 0, 3);
        // R
        claimAndRegisterEntries(user1, 0, 6);

        checkStateAfterStepOne(user1, 3, 3, true);
    }

    function test_NVR() public {
        // N
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 3);
        // R
        claimAndRegisterEntries(user1, 0, 6);

        checkStateAfterStepOne(user1, 3, 3, true);
    }

    function test_VNR() public {
        // V
        vest(user1, 0, 3);
        // N
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        claimAndRegisterEntries(user1, 0, 6);

        checkStateAfterStepOne(user1, 3, 3, true);
    }

    /*//////////////////////////////////////////////////////////////
                       STRANGE FLOWS UP TO STEP 2
    //////////////////////////////////////////////////////////////*/

    function test_RNC() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // N
        createRewardEscrowEntryV1(user1, 1 ether);
        // C
        confirm(user1, 0, 6);

        checkStateAfterStepTwo(user1, 0, 0, false);
    }

    function test_RNVC() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // N
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 3);
        // C
        confirm(user1, 0, 6);

        checkStateAfterStepTwo(user1, 0, 3, false);
    }

    function test_RVNC() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 3);
        // N
        createRewardEscrowEntryV1(user1, 1 ether);
        // C
        confirm(user1, 0, 6);

        checkStateAfterStepTwo(user1, 0, 3, false);
    }

}

// Up to step 2
// RNVRVC
// RVNRVC
// RVRNVC
// RVRVNC

// RNVCRVC
// RVNCRVC
// RVCNRVC
// RVCRNVC
// RVCRVNC

// Up to step 3
// CVM
// CNM

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
