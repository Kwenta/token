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
import {IStakingRewardsIntegrator} from
    "../../../contracts/interfaces/IStakingRewardsIntegrator.sol";
import "../utils/Constants.t.sol";
import {EscrowMigratorTestHelpers} from "../utils/helpers/EscrowMigratorTestHelpers.t.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// TODO: rename contract and fix ci related error
contract StakingV2MigrationForkTests is EscrowMigratorTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    IStakingRewardsIntegrator internal integrator;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        vm.rollFork(106_878_447);

        // define main contracts
        kwenta = Kwenta(OPTIMISM_KWENTA_TOKEN);
        IERC20 usdc = IERC20(OPTIMISM_USDC_TOKEN);
        rewardEscrowV1 = RewardEscrow(OPTIMISM_REWARD_ESCROW_V1);
        supplySchedule = SupplySchedule(OPTIMISM_SUPPLY_SCHEDULE);
        stakingRewardsV1 = StakingRewards(OPTIMISM_STAKING_REWARDS_V1);

        // define main addresses
        owner = OPTIMISM_PDAO;
        treasury = OPTIMISM_TREASURY_DAO;
        user1 = OPTIMISM_RANDOM_STAKING_USER_1;
        user2 = OPTIMISM_RANDOM_STAKING_USER_2;
        user3 = OPTIMISM_RANDOM_STAKING_USER_3;
        user4 = createUser();
        integrator = IStakingRewardsIntegrator(OPTIMISM_STAKING_V1_INTEGRATOR_1);

        // set owners address code to trick the test into allowing onlyOwner functions to be called via script
        vm.etch(owner, address(new Migrate()).code);

        (rewardEscrowV2, stakingRewardsV2, escrowMigrator, rewardsNotifier) = Migrate(owner)
            .runCompleteMigrationProcess({
            _owner: owner,
            _kwenta: address(kwenta),
            _usdc: address(usdc),
            _supplySchedule: address(supplySchedule),
            _treasuryDAO: treasury,
            _rewardEscrowV1: address(rewardEscrowV1),
            _printLogs: false
        });

        assertEq(stakingRewardsV2.rewardRate(), 0);
        assertEq(kwenta.balanceOf(address(stakingRewardsV2)), 0);

        // mint first rewards into V2
        uint256 timeOfNextMint =
            supplySchedule.lastMintEvent() + supplySchedule.MINT_PERIOD_DURATION();
        vm.warp(timeOfNextMint + 1);
        supplySchedule.mint();

        assertGt(stakingRewardsV2.rewardRate(), 0);
        assertGt(kwenta.balanceOf(address(stakingRewardsV2)), 0);

        // call updateReward in staking rewards v1
        vm.prank(treasury);
        stakingRewardsV1.unstake(1);

        // check no more new rewards in v1
        assertEq(stakingRewardsV1.lastTimeRewardApplicable() - stakingRewardsV1.lastUpdateTime(), 0);
        assertEq(stakingRewardsV1.lastTimeRewardApplicable(), stakingRewardsV1.periodFinish());
    }

    /*//////////////////////////////////////////////////////////////
                              PAUSABILITY
    //////////////////////////////////////////////////////////////*/

    function test_Pause_Is_Only_Owner() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        escrowMigrator.pauseEscrowMigrator();
    }

    function test_Unpause_Is_Only_Owner() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        escrowMigrator.unpauseEscrowMigrator();
    }

    function test_Pause_Register() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // pause
        vm.prank(owner);
        escrowMigrator.pauseEscrowMigrator();

        // attempt to register and fail
        vm.prank(user1);
        vm.expectRevert("Pausable: paused");
        escrowMigrator.registerEntries(_entryIDs);

        // unpause
        vm.prank(owner);
        escrowMigrator.unpauseEscrowMigrator();

        // register and succeed
        vm.prank(user1);
        escrowMigrator.registerEntries(_entryIDs);

        checkStateAfterStepOne(user1, _entryIDs, true);
    }

    function test_Pause_Migrate() public {
        // register, vest and approve
        (uint256[] memory _entryIDs,,) = claimRegisterVestAndApprove(user1);

        // pause
        vm.prank(owner);
        escrowMigrator.pauseEscrowMigrator();

        // attempt to migrate and fail
        vm.prank(user1);
        vm.expectRevert("Pausable: paused");
        escrowMigrator.migrateEntries(user1, _entryIDs);

        // unpause
        vm.prank(owner);
        escrowMigrator.unpauseEscrowMigrator();

        // migrate and succeed
        vm.prank(user1);
        escrowMigrator.migrateEntries(user1, _entryIDs);

        checkStateAfterStepThree(user1, _entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                              TEST TOTALS
    //////////////////////////////////////////////////////////////*/

    function test_Total_Registered() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // check initial state
        assertEq(escrowMigrator.totalRegistered(), 0);

        uint256 totalRegistered;
        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            (, uint256 escrowAmount,) = rewardEscrowV1.getVestingEntry(user1, entryID);
            totalRegistered += escrowAmount;
        }

        // register
        registerEntries(user1, _entryIDs);

        // check final state
        assertEq(escrowMigrator.totalRegistered(), totalRegistered);
    }

    function test_Total_Registered_Fuzz(uint8 numToRegister) public {
        (uint256[] memory allEntryIDs,) = claimAndCheckInitialState(user1);
        uint256[] memory registeredEntryIDs = new uint256[](numToRegister);
        // check initial state
        assertEq(escrowMigrator.totalRegistered(), 0);

        uint256 totalRegistered;
        for (uint256 i = 0; i < min(allEntryIDs.length, numToRegister); i++) {
            uint256 entryID = allEntryIDs[i];
            (, uint256 escrowAmount,) = rewardEscrowV1.getVestingEntry(user1, entryID);
            totalRegistered += escrowAmount;
            registeredEntryIDs[i] = entryID;
        }

        // register
        registerEntries(user1, registeredEntryIDs);

        // check final state
        assertEq(escrowMigrator.totalRegistered(), totalRegistered);
    }

    function test_Total_Migrated() public {
        // register, vest and approve
        (uint256[] memory _entryIDs,,) = claimRegisterVestAndApprove(user1);

        // check initial state
        assertEq(escrowMigrator.totalMigrated(), 0);

        uint256 totalMigrated;
        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            (uint256 escrowAmount,) = escrowMigrator.registeredVestingSchedules(user1, entryID);
            totalMigrated += escrowAmount;
        }

        // migrate
        migrateEntries(user1, _entryIDs);

        // check final state
        assertEq(escrowMigrator.totalMigrated(), totalMigrated);
    }

    function test_Total_Migrated_Fuzz(uint8 numToMigrate) public {
        // register, vest and approve
        (uint256[] memory allEntryIDs,,) = claimRegisterVestAndApprove(user1);
        uint256[] memory migratedEntryIDs = new uint256[](numToMigrate);

        // check initial state
        assertEq(escrowMigrator.totalMigrated(), 0);

        uint256 totalMigrated;
        for (uint256 i = 0; i < min(allEntryIDs.length, numToMigrate); i++) {
            uint256 entryID = allEntryIDs[i];
            (uint256 escrowAmount,) = escrowMigrator.registeredVestingSchedules(user1, entryID);
            totalMigrated += escrowAmount;
            migratedEntryIDs[i] = entryID;
        }

        // migrate
        migrateEntries(user1, migratedEntryIDs);

        // check final state
        assertEq(escrowMigrator.totalMigrated(), totalMigrated);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function test_getRegisteredVestingSchedules() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        registerEntries(user1, _entryIDs);

        IEscrowMigrator.VestingEntryWithID[] memory registeredEntries =
            escrowMigrator.getRegisteredVestingSchedules(user1, 0, 10);

        for (uint256 i = 0; i < registeredEntries.length; i++) {
            IEscrowMigrator.VestingEntryWithID memory entry = registeredEntries[i];
            (, uint256 escrowAmount,) = rewardEscrowV1.getVestingEntry(user1, entry.entryID);

            assertEq(entry.entryID, _entryIDs[i]);
            assertEq(entry.escrowAmount, escrowAmount);
            assertEq(entry.migrated, false);
        }
    }

    function test_getRegisteredVestingSchedules_Wrong_Account() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        registerEntries(user1, _entryIDs);

        IEscrowMigrator.VestingEntryWithID[] memory registeredEntries =
            escrowMigrator.getRegisteredVestingSchedules(user2, 0, 10);

        assertEq(registeredEntries.length, 0);
    }

    function test_getRegisteredVestingSchedules_Size_0() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        registerEntries(user1, _entryIDs);

        IEscrowMigrator.VestingEntryWithID[] memory registeredEntries =
            escrowMigrator.getRegisteredVestingSchedules(user1, 0, 0);

        assertEq(registeredEntries.length, 0);
    }

    function test_getRegisteredVestingSchedules_Invalid_Index() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        registerEntries(user1, _entryIDs);

        IEscrowMigrator.VestingEntryWithID[] memory registeredEntries =
            escrowMigrator.getRegisteredVestingSchedules(user1, 100, 5);

        assertEq(registeredEntries.length, 0);
    }

    function test_getRegisteredVestingEntryIDs() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        registerEntries(user1, _entryIDs);

        uint256[] memory registeredEntries =
            escrowMigrator.getRegisteredVestingEntryIDs(user1, 0, 10);

        for (uint256 i = 0; i < registeredEntries.length; i++) {
            uint256 entry = registeredEntries[i];
            assertEq(entry, _entryIDs[i]);
        }
    }

    function test_getRegisteredVestingEntryIDs_Wrong_Account() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        registerEntries(user1, _entryIDs);

        uint256[] memory registeredEntries =
            escrowMigrator.getRegisteredVestingEntryIDs(user2, 0, 10);

        assertEq(registeredEntries.length, 0);
    }

    function test_getRegisteredVestingEntryIDs_Size_0() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        registerEntries(user1, _entryIDs);

        uint256[] memory registeredEntries =
            escrowMigrator.getRegisteredVestingEntryIDs(user1, 0, 0);

        assertEq(registeredEntries.length, 0);
    }

    function test_getRegisteredVestingEntryIDs_Invalid_Index() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        registerEntries(user1, _entryIDs);

        uint256[] memory registeredEntries =
            escrowMigrator.getRegisteredVestingEntryIDs(user1, 100, 5);

        assertEq(registeredEntries.length, 0);
    }

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

    function test_Cannot_Register_After_Deadline() public {
        // check initial state
        claimAndCheckInitialState(user1);

        // step 1
        registerEntries(user1, 0, 5);

        // attempt to register further entries after the deadline
        vm.warp(block.timestamp + escrowMigrator.MIGRATION_DEADLINE() + 1);
        uint256[] memory extraEntryIDs = getEntryIDs(user1, 5, 10);
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.DeadlinePassed.selector);
        escrowMigrator.registerEntries(extraEntryIDs);

        // check final state
        checkStateAfterStepOne(user1, 0, 5, true);
    }

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

    function test_Can_Register_Without_Claiming_First() public {
        // check initial state
        (uint256[] memory _entryIDs,) = checkStateBeforeStepOne(user1);

        // step 1
        vm.prank(user1);
        escrowMigrator.registerEntries(_entryIDs);

        checkStateAfterStepOne(user1, _entryIDs, true);
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

    function test_Can_Register_Mature_Entries() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // fast forward until all entries are mature
        vm.warp(block.timestamp + 52 weeks);

        // step 1
        registerEntries(user1, _entryIDs);

        // check final state
        checkStateAfterStepOne(user1, _entryIDs, true);
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

        checkStateAfterStepThree(user1, 0, 10);
    }

    /*//////////////////////////////////////////////////////////////
                              STEP 3 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Step_3_Normal() public {
        // complete step 1
        (uint256[] memory _entryIDs,,) = claimRegisterVestAndApprove(user1);

        // step 2 - migrate entries
        migrateEntries(user1, _entryIDs);

        // check final state
        checkStateAfterStepThree(user1, _entryIDs);
    }

    function test_Step_3_Two_Rounds() public {
        // complete step 1
        claimRegisterVestAndApprove(user1);

        // step 2 - migrate entries
        migrateEntries(user1, 0, 10);
        migrateEntries(user1, 10, 7);

        // check final state
        checkStateAfterStepThree(user1, 0, 17);
    }

    function test_Step_3_N_Rounds_Fuzz(uint8 _numRounds, uint8 _numPerRound) public {
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
        checkStateAfterStepThree(user1, 0, numMigrated);
    }

    function test_Step_3_Different_To_Address() public {
        // complete step 1
        (uint256[] memory _entryIDs,,) = claimRegisterVestAndApprove(user1);

        // step 2 - migrate entries
        vm.prank(user1);
        escrowMigrator.migrateEntries(user2, _entryIDs);

        // check final state
        checkStateAfterStepThree(user1, user2, _entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                           STEP 3 EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_Step_Cannot_Migrate_After_Two_Weeks() public {
        // complete step 1
        (uint256[] memory _entryIDs,,) = claimRegisterVestAndApprove(user1);

        vm.warp(block.timestamp + escrowMigrator.MIGRATION_DEADLINE() + 1);

        // step 3.2 - migrate entries
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.DeadlinePassed.selector);
        escrowMigrator.migrateEntries(user1, _entryIDs);
    }

    function test_Can_Migrate_Mature_Entries() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // fast forward until all entries are mature
        vm.warp(block.timestamp + 52 weeks);

        // step 1
        registerVestAndApprove(user1, _entryIDs);
        migrateEntries(user1, _entryIDs);

        // check final state
        checkStateAfterStepThree(user1, _entryIDs);
    }

    function test_Can_Migrate_Entries_Matured_After_Registering() public {
        // fast forward until most entries are mature
        vm.warp(block.timestamp + 50 weeks);

        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // step 1
        registerVestAndApprove(user1, _entryIDs);

        // fast forward until all entries are mature
        vm.warp(block.timestamp + escrowMigrator.MIGRATION_DEADLINE());

        migrateEntries(user1, _entryIDs);

        // check final state
        checkStateAfterStepThree(user1, _entryIDs);
    }

    function test_Payment_Cost_Takes_Account_Of_Escrow_Vested_At_Start() public {
        // give user extra funds so they could in theory overpay
        vm.prank(treasury);
        kwenta.transfer(user3, 50 ether);

        uint256 vestedBalance = rewardEscrowV1.totalVestedAccountBalance(user3);
        assertGt(vestedBalance, 0);

        // fully migrate entries
        (uint256[] memory _entryIDs,,) = claimAndFullyMigrate(user3);

        // check final state
        /// @dev skip first entry as it was vested before migration, so couldn't be migrated
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user3, 1, _entryIDs.length);
        checkStateAfterStepThree(user3, _entryIDs);
    }

    function test_Step_3_Must_Pay() public {
        // complete step 1
        (uint256[] memory _entryIDs,) = claimRegisterAndVestAllEntries(user1);

        // step 3.2 - migrate entries
        vm.prank(user1);
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        escrowMigrator.migrateEntries(user1, _entryIDs);
    }

    function test_Step_3_Must_Pay_Fuzz(uint256 approveAmount) public {
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

    function test_Cannot_Migrate_Non_Vested_Entries() public {
        // give escrow migrator funds so it could be cheated
        vm.prank(treasury);
        kwenta.transfer(address(escrowMigrator), 50 ether);

        // complete step 1
        claimAndRegisterAllEntries(user1);

        vest(user1, 0, 15);
        approve(user1);

        // step 2 - migrate entries
        migrateEntries(user1, 0, 17);

        // check final state
        checkStateAfterStepThree(user1, 0, 15);
    }

    function test_Cannot_Migrate_Non_Registered_Entries() public {
        // complete step 1
        claimRegisterVestAndApprove(user1, 0, 10);

        // step 2 - migrate extra entries
        migrateEntries(user1, 0, 17);

        // check final state
        checkStateAfterStepThree(user1, 0, 10);
    }

    function test_Cannot_Migrate_Non_Registered_Late_Vested_Entries() public {
        // complete step 1
        claimRegisterAndVestEntries(user1, 0, 10);

        // vest extra entries and approve
        vestAndApprove(user1, 0, 17);

        // step 2 - migrate extra entries
        migrateEntries(user1, 0, 17);

        // check final state
        checkStateAfterStepThree(user1, 0, 10);
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
        checkStateAfterStepThree(user1, 0, 15);
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
        checkStateAfterStepThree(user1, 0, 0);
    }

    function test_Cannot_Migrate_Someone_Elses_Entries() public {
        // complete step 1
        (uint256[] memory user1EntryIDs,,) = claimRegisterVestAndApprove(user1);
        claimRegisterVestAndApprove(user2);

        // step 2 - user2 attempts to migrate user1's entries
        migrateEntries(user2, user1EntryIDs);

        // check final state - user2 didn't manage to migrate any entries
        checkStateAfterStepThree(user2, 0, 0);
    }

    function test_Cannot_Migrate_On_Behalf_Of_Someone() public {
        // complete step 1
        (uint256[] memory user1EntryIDs,,) = claimRegisterVestAndApprove(user1);
        claimRegisterVestAndApprove(user2);

        // step 2 - user2 attempts to migrate user1's entries
        vm.prank(user2);
        escrowMigrator.migrateEntries(user1, user1EntryIDs);

        // check final state - user2 didn't manage to migrate any entries
        checkStateAfterStepThree(user1, 0, 0);
    }

    function test_Cannot_Bypass_Unstaking_Cooldown_Lock() public {
        // this is the malicious entry - the duration is set to 1
        createRewardEscrowEntryV1(user1, 50 ether, 1);

        (uint256[] memory _entryIDs, uint256 numVestingEntries,) = claimAndFullyMigrate(user1);
        checkStateAfterStepThree(user1, _entryIDs);

        // specifically
        uint256[] memory migratedEntryIDs =
            rewardEscrowV2.getAccountVestingEntryIDs(user1, numVestingEntries - 2, 1);
        uint256 maliciousEntryID = migratedEntryIDs[0];
        (uint256 endTime, uint256 escrowAmount, uint256 duration, uint256 earlyVestingFee) =
            rewardEscrowV2.getVestingEntry(maliciousEntryID);
        assertEq(endTime, block.timestamp + stakingRewardsV2.cooldownPeriod());
        assertEq(escrowAmount, 50 ether);
        assertEq(duration, stakingRewardsV2.cooldownPeriod());
        assertEq(earlyVestingFee, 90);
    }

    function test_Cannot_Migrate_In_Non_Initiated_State() public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);

        // attempt in non initiated state
        assertEq(escrowMigrator.initializationTime(user1), 0);

        // step 2 - migrate entries
        vm.prank(user1);
        vm.expectRevert(IEscrowMigrator.MustBeInitiated.selector);
        escrowMigrator.migrateEntries(user1, _entryIDs);
    }

    function test_Cannot_Use_Zero_To_Address() public {
        // complete step 1
        (uint256[] memory _entryIDs,,) = claimRegisterVestAndApprove(user1);

        // step 2 - migrate entries to zero address
        vm.prank(user1);
        vm.expectRevert("ERC721: mint to the zero address");
        escrowMigrator.migrateEntries(address(0), _entryIDs);
    }

    function test_Migrate_Entries_In_Funny_Order_Fuzz(uint256 salt) public {
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(user1);
        uint256[] memory entriesToRegister = new uint256[](_entryIDs.length);
        uint256[] memory entriesToVest = new uint256[](_entryIDs.length);
        uint256[] memory entriesToMigrate = new uint256[](_entryIDs.length);
        uint256[] memory entriesFullyMigrated = new uint256[](_entryIDs.length);

        uint256 j;
        uint256 numOfEntriesFullyMigrated;
        uint256 totalEscrowMigrated;
        for (uint256 i = _entryIDs.length; i > 0; i--) {
            bool fullyMigrated = true;
            uint256 entryID = _entryIDs[i - 1];
            if (flipCoin(salt)) {
                entriesToRegister[j] = entryID;
            } else {
                fullyMigrated = false;
            }
            if (flipCoin(salt)) {
                entriesToVest[j] = entryID;
            } else {
                fullyMigrated = false;
            }
            if (flipCoin(salt)) {
                entriesToMigrate[j] = entryID;
            } else {
                fullyMigrated = false;
            }

            if (fullyMigrated) {
                entriesFullyMigrated[j] = entryID;
                numOfEntriesFullyMigrated++;
                (, uint256 escrowAmount,) = rewardEscrowV1.getVestingEntry(user1, entryID);
                totalEscrowMigrated += escrowAmount;
            }
            j++;
        }
        uint256[] memory entriesFullyMigratedList = new uint256[](numOfEntriesFullyMigrated);
        uint256 k;
        for (uint256 i; i < entriesFullyMigrated.length; i++) {
            if (entriesFullyMigrated[i] != 0) {
                entriesFullyMigratedList[k] = entriesFullyMigrated[i];
                k++;
            }
        }

        // step 1 - register entries
        registerEntries(user1, entriesToRegister);

        // step 2 - vest entries
        vestAndApprove(user1, entriesToVest);

        // step 3 - migrate entries
        migrateEntries(user1, entriesToMigrate);

        // check final state
        assertEq(rewardEscrowV2.balanceOf(user1), numOfEntriesFullyMigrated);
        checkStateAfterStepThreeAssertions(
            user1, user1, entriesFullyMigratedList, totalEscrowMigrated
        );
    }

    /*//////////////////////////////////////////////////////////////
                          STEP 3 STATE LIMITS
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Migrate_Initiated_Without_Registering_Anything() public {
        // complete step 1
        claimAndRegisterEntries(user1, 0, 0);

        // step 2 - migrate entries
        migrateEntries(user1, 0, 17);
        vm.prank(user1);

        checkStateAfterStepThree(user1, 0, 0);
    }

    function test_Can_Migrate_In_Completed_State() public {
        // move to completed state
        claimAndFullyMigrate(user1);

        createRewardEscrowEntryV1(user1, 10 ether);
        createRewardEscrowEntryV1(user1, 10 ether);
        createRewardEscrowEntryV1(user1, 10 ether);

        fullyMigrate(user1, 17, 3);

        checkStateAfterStepThree(user1, 0, 20);
    }

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

        assertEq(total, 3.81970665526471165 ether);
        assertEq(totalFee, 13.426448456149921258 ether);

        // step 1
        vm.prank(user1);
        escrowMigrator.registerEntries(entryIDs);

        uint256 step2UserBalance = kwenta.balanceOf(user1);
        uint256 step2MigratorBalance = kwenta.balanceOf(address(escrowMigrator));

        // step 2.1 - vest
        vm.prank(user1);
        rewardEscrowV1.vest(entryIDs);

        uint256 step2UserBalanceAfterVest = kwenta.balanceOf(user1);
        uint256 step2MigratorBalanceAfterVest = kwenta.balanceOf(address(escrowMigrator));
        assertEq(step2UserBalanceAfterVest, step2UserBalance + total);
        assertEq(step2MigratorBalanceAfterVest, step2MigratorBalance + totalFee);

        // step 2.2 - pay for migration
        vm.prank(user1);
        kwenta.approve(address(escrowMigrator), total);

        // step 2.3 - migrate entries
        vm.prank(user1);
        escrowMigrator.migrateEntries(user1, entryIDs);

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
    /// R = register, V = vest, M = migrate, C = create new escrow entry
    /// So for example, RVC means register, vest, confirm, in that order

    function test_RVRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 5);
        // V
        vest(user1, 0, 5);
        // R
        registerEntries(user1, 5, 5);
        // V
        vest(user1, 5, 5);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepThree(user1, 0, 10);
    }

    function test_RVMRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 5);
        // M
        approveAndMigrate(user1, 0, 5);
        // R
        registerEntries(user1, 6, 4);
        // V
        vest(user1, 5, 5);
        // M
        approveAndMigrate(user1, 5, 5);

        checkStateAfterStepThree(user1, 0, 10);
    }

    /*//////////////////////////////////////////////////////////////
                       STRANGE FLOWS UP TO STEP 1
    //////////////////////////////////////////////////////////////*/

    function test_CR() public {
        // C
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

    function test_CVR() public {
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 3);
        // R
        claimAndRegisterEntries(user1, 0, 6);

        checkStateAfterStepOne(user1, 3, 3, true);
    }

    function test_VCR() public {
        // V
        vest(user1, 0, 3);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        claimAndRegisterEntries(user1, 0, 6);

        checkStateAfterStepOne(user1, 3, 3, true);
    }

    /*//////////////////////////////////////////////////////////////
                       STRANGE FLOWS UP TO STEP 3
    //////////////////////////////////////////////////////////////*/

    function test_RCM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 6);

        checkStateAfterStepThree(user1, 0, 0);
    }

    function test_RCVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 3);
        // M
        approveAndMigrate(user1, 0, 6);

        checkStateAfterStepThree(user1, 0, 3);
    }

    function test_RVCM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 3);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 6);

        checkStateAfterStepThree(user1, 0, 3);
    }

    function test_RCVRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 3);
        // R
        registerEntries(user1, 6, 4);
        // V
        vest(user1, 3, 3);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepThree(user1, 0, 6);
    }

    function test_RVCRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 3);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        registerEntries(user1, 6, 4);
        // V
        vest(user1, 3, 3);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepThree(user1, 0, 6);
    }

    function test_RVRCVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 3);
        // R
        registerEntries(user1, 6, 4);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 3, 3);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepThree(user1, 0, 6);
    }

    function test_RVRVCM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 3);
        // R
        registerEntries(user1, 6, 4);
        // V
        vest(user1, 3, 7);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepThree(user1, 0, 10);
    }

    function test_RCVMRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 3);
        // M
        approveAndMigrate(user1, 0, 6);
        // R
        registerEntries(user1, 6, 4);
        // V
        vest(user1, 3, 7);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepThree(user1, 0, 10);
    }

    function test_RVCMRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 6);
        // V
        vest(user1, 0, 3);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 6);
        // R
        registerEntries(user1, 6, 4);
        // V
        vest(user1, 3, 7);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepThree(user1, 0, 10);
    }

    function test_RVMCRVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 10);
        // V
        vest(user1, 0, 3);
        // M
        approveAndMigrate(user1, 0, 6);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        registerEntries(user1, 10, 4);
        // V
        vest(user1, 3, 7);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepThree(user1, 0, 10);
    }

    function test_RVMRCVM() public {
        // R
        claimAndRegisterEntries(user1, 0, 10);
        // V
        vest(user1, 0, 3);
        // M
        approveAndMigrate(user1, 0, 6);
        // R
        registerEntries(user1, 10, 7);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 3, 14);
        // M
        approveAndMigrate(user1, 3, 17);

        checkStateAfterStepThree(user1, 0, 17);
    }

    function test_RVMRVCM() public {
        // R
        claimAndRegisterEntries(user1, 0, 10);
        // V
        vest(user1, 0, 3);
        // M
        approveAndMigrate(user1, 0, 6);
        // R
        registerEntries(user1, 10, 7);
        // V
        vest(user1, 3, 14);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 3, 17);

        checkStateAfterStepThree(user1, 0, 17);
    }

    /*//////////////////////////////////////////////////////////////
                      STRANGE FLOWS BEYOND STEP 3
    //////////////////////////////////////////////////////////////*/

    function test_MVM() public {
        claimRegisterAndVestEntries(user1, 0, 10);

        // M
        approveAndMigrate(user1, 0, 10);
        // V
        vest(user1, 0, 17);
        // M
        approveAndMigrate(user1, 0, 10);

        checkStateAfterStepThree(user1, 0, 10);
    }

    function test_MCM() public {
        claimRegisterAndVestEntries(user1, 0, 17);

        // M
        approveAndMigrate(user1, 0, 17);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepThree(user1, 0, 17);
    }

    function test_MCVM() public {
        claimRegisterAndVestEntries(user1, 0, 17);

        // M
        approveAndMigrate(user1, 0, 17);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 18);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepThree(user1, 0, 17);
    }

    function test_MVCM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // V
        vest(user1, 0, 15);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepThree(user1, 0, 15);
    }

    function test_MRVM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // R
        registerEntries(user1, 15, 2);
        // V
        vest(user1, 0, 17);
        // M
        approveAndMigrate(user1, 0, 17);

        checkStateAfterStepThree(user1, 0, 17);
    }

    function test_MRCM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // R
        registerEntries(user1, 15, 2);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepThree(user1, 0, 15);
    }

    function test_MCRM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        registerEntries(user1, 15, 2);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepThree(user1, 0, 15);
    }

    function test_MRCVM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // R
        registerEntries(user1, 15, 2);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 18);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepThree(user1, 0, 17);
    }

    function test_MRVCM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // R
        registerEntries(user1, 15, 2);
        // V
        vest(user1, 0, 17);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepThree(user1, 0, 17);
    }

    function test_MVRCM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // V
        vest(user1, 0, 17);
        // R
        registerEntries(user1, 15, 2);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepThree(user1, 0, 15);
    }

    function test_MVCRM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // V
        vest(user1, 0, 17);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        registerEntries(user1, 15, 3);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepThree(user1, 0, 15);
    }

    function test_MCVRM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // V
        vest(user1, 0, 17);
        // R
        registerEntries(user1, 15, 3);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepThree(user1, 0, 15);
    }

    function test_MCRVM() public {
        claimRegisterAndVestEntries(user1, 0, 15);

        // M
        approveAndMigrate(user1, 0, 15);
        // C
        createRewardEscrowEntryV1(user1, 1 ether);
        // R
        registerEntries(user1, 15, 3);
        // V
        vest(user1, 0, 17);
        // M
        approveAndMigrate(user1, 0, 18);

        checkStateAfterStepThree(user1, 0, 17);
    }

    /*//////////////////////////////////////////////////////////////
                            INTEGRATOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Integrator_Step_1_Normal() public {
        address beneficiary = integrator.beneficiary();
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(address(integrator));
        checkStateBeforeStepOne(beneficiary);

        registerIntegratorEntries(integrator, _entryIDs);

        // check final state
        checkStateAfterStepOne(address(integrator), _entryIDs, true);
    }

    function test_Integrator_Step_1_Two_Rounds() public {
        // check initial state
        (uint256[] memory _entryIDs,) = claimAndCheckInitialState(address(integrator));

        // step 1 - register some entries
        registerIntegratorEntries(integrator, 0, 20);
        registerIntegratorEntries(integrator, 20, 25);

        // check final state
        checkStateAfterStepOne(address(integrator), _entryIDs, true);
    }

    function test_Integrator_Step_3_Normal() public {
        // complete step 1
        address beneficiary = integrator.beneficiary();
        (uint256[] memory _entryIDs,,) = claimRegisterVestAndApproveIntegrator(integrator);

        // step 2 - migrate entries
        migrateIntegratorEntries(integrator, _entryIDs, beneficiary);

        // check final state
        checkStateAfterStepThree(address(integrator), beneficiary, _entryIDs);
    }

    function test_Integrator_Step_3_Different_To_Address() public {
        // complete step 1
        (uint256[] memory _entryIDs,,) = claimRegisterVestAndApproveIntegrator(integrator);

        // step 2 - migrate entries
        migrateIntegratorEntries(integrator, _entryIDs, user1);

        // check final state
        checkStateAfterStepThree(address(integrator), user1, _entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                         INTEGRATOR EDGE CASES
    //////////////////////////////////////////////////////////////*/

    function test_Must_Be_Integrator_Beneficiary() public {
        vm.expectRevert(IEscrowMigrator.NotApproved.selector);
        escrowMigrator.registerIntegratorEntries(address(integrator), entryIDs);

        vm.expectRevert(IEscrowMigrator.NotApproved.selector);
        escrowMigrator.migrateIntegratorEntries(address(integrator), address(this), entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                          FUND RECOVERY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_setTreasuryDAO() public {
        assertEq(escrowMigrator.treasuryDAO(), treasury);

        // Only owner can set the treasury DAO address
        vm.expectRevert("Ownable: caller is not the owner");
        escrowMigrator.setTreasuryDAO(user1);

        // Owner can set the treasury DAO address
        vm.prank(owner);
        escrowMigrator.setTreasuryDAO(user1);

        // Check that the treasury DAO address has been updated
        assertEq(escrowMigrator.treasuryDAO(), user1);

        // Owner cannot set treasury address to zero address
        vm.prank(owner);
        vm.expectRevert(IEscrowMigrator.ZeroAddress.selector);
        escrowMigrator.setTreasuryDAO(address(0));

        // Owner can set the treasury DAO address back to the original
        vm.prank(owner);
        escrowMigrator.setTreasuryDAO(treasury);

        // Check that the treasury DAO address has been updated
        assertEq(escrowMigrator.treasuryDAO(), treasury);
    }

    function test_Cannot_Update_Total_Locked_For_Unregistered_User() public {
        escrowMigrator.updateTotalLocked(user1);
        assertFalse(escrowMigrator.lockedFundsAccountedFor(user1));
    }

    function test_OnlyOwner_Can_Recover_Excess_Funds() public {
        vm.expectRevert("Ownable: caller is not the owner");
        escrowMigrator.recoverExcessFunds();

        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();
    }

    function test_Fund_Recovery_User_Regisered() public {
        vm.prank(user1);
        stakingRewardsV1.getReward();
        vm.prank(user2);
        stakingRewardsV1.getReward();
        vm.prank(user3);
        stakingRewardsV1.getReward();

        uint256 userBalanceBeforeVest = kwenta.balanceOf(user1);
        uint256 escrowMigratorBalanceBeforeVest = kwenta.balanceOf(address(escrowMigrator));

        uint256[] memory _entryIDs = getEntryIDs(user1);
        (uint256 total, uint256 fee) = rewardEscrowV1.getVestingQuantity(user1, _entryIDs);
        (uint256 user2Total, uint256 user2Fee) =
            rewardEscrowV1.getVestingQuantity(user2, getEntryIDs(user2));
        (uint256 user3Total, uint256 user3Fee) =
            rewardEscrowV1.getVestingQuantity(user3, getEntryIDs(user3));

        vest(user1);

        assertEq(escrowMigrator.totalRegistered(), 0);
        assertEq(escrowMigrator.totalMigrated(), 0);
        assertEq(kwenta.balanceOf(address(escrowMigrator)), fee);
        assertEq(kwenta.balanceOf(user1) - userBalanceBeforeVest, total);
        assertEq(kwenta.balanceOf(address(escrowMigrator)) - escrowMigratorBalanceBeforeVest, fee);

        claimAndFullyMigrate(user2);
        claimAndRegisterEntries(user3);

        assertEq(
            escrowMigrator.totalRegistered(),
            escrowMigrator.totalEscrowRegistered(user2)
                + escrowMigrator.totalEscrowRegistered(user3)
        );
        assertEq(
            escrowMigrator.totalEscrowRegistered(user2), rewardEscrowV2.escrowedBalanceOf(user2)
        );
        assertEq(escrowMigrator.totalEscrowRegistered(user2), user2Total + user2Fee);
        assertEq(escrowMigrator.totalEscrowRegistered(user3), user3Total + user3Fee);
        assertEq(escrowMigrator.totalMigrated(), escrowMigrator.totalEscrowRegistered(user2));
        assertEq(escrowMigrator.totalMigrated(), user2Total + user2Fee);
        assertEq(kwenta.balanceOf(address(escrowMigrator)), fee);
        assertEq(kwenta.balanceOf(address(escrowMigrator)) - escrowMigratorBalanceBeforeVest, fee);

        uint256 balanceBefore = kwenta.balanceOf(treasury);

        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();

        uint256 balanceAfter = kwenta.balanceOf(treasury);

        assertEq(balanceAfter - balanceBefore, fee - user3Total - user3Fee);
        assertEq(kwenta.balanceOf(address(escrowMigrator)), user3Total + user3Fee);

        vestApproveAndMigrate(user3);
        checkStateAfterStepThree(user3, 1, 12);
    }

    function test_Fund_Recovery_Nothing_To_Recover() public {
        vm.prank(user1);
        stakingRewardsV1.getReward();
        vm.prank(user2);
        stakingRewardsV1.getReward();
        vm.prank(user3);
        stakingRewardsV1.getReward();

        uint256 user1Balance = kwenta.balanceOf(user1);
        uint256 escrowMigratorBalance = kwenta.balanceOf(address(escrowMigrator));

        (uint256 user2Total, uint256 user2Fee) =
            rewardEscrowV1.getVestingQuantity(user2, getEntryIDs(user2));
        (uint256 user3Total, uint256 user3Fee) =
            rewardEscrowV1.getVestingQuantity(user3, getEntryIDs(user3));

        assertEq(escrowMigrator.totalRegistered(), 0);
        assertEq(escrowMigrator.totalMigrated(), 0);
        assertEq(kwenta.balanceOf(address(escrowMigrator)), 0);
        assertEq(kwenta.balanceOf(user1) - user1Balance, 0);
        assertEq(kwenta.balanceOf(address(escrowMigrator)) - escrowMigratorBalance, 0);

        claimAndFullyMigrate(user2);
        claimAndRegisterEntries(user3);

        assertEq(
            escrowMigrator.totalRegistered(),
            escrowMigrator.totalEscrowRegistered(user2)
                + escrowMigrator.totalEscrowRegistered(user3)
        );
        assertEq(
            escrowMigrator.totalEscrowRegistered(user2), rewardEscrowV2.escrowedBalanceOf(user2)
        );
        assertEq(escrowMigrator.totalEscrowRegistered(user2), user2Total + user2Fee);
        assertEq(escrowMigrator.totalEscrowRegistered(user3), user3Total + user3Fee);
        assertEq(escrowMigrator.totalMigrated(), escrowMigrator.totalEscrowRegistered(user2));
        assertEq(escrowMigrator.totalMigrated(), user2Total + user2Fee);
        assertEq(kwenta.balanceOf(address(escrowMigrator)), 0);
        assertEq(kwenta.balanceOf(address(escrowMigrator)) - escrowMigratorBalance, 0);

        uint256 balanceBefore = kwenta.balanceOf(treasury);

        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();

        uint256 balanceAfter = kwenta.balanceOf(treasury);

        assertEq(balanceAfter - balanceBefore, 0);
        assertEq(kwenta.balanceOf(address(escrowMigrator)), 0);

        vestApproveAndMigrate(user3);
        checkStateAfterStepThree(user3, 1, 12);
    }

    function test_User_Regisered_Cannot_Free_Frozen_Funds_If_Deadline_Not_Passed() public {
        vest(user1);
        claimAndFullyMigrate(user2);
        claimAndRegisterEntries(user3);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        escrowMigrator.updateTotalLocked(users);

        assertEq(escrowMigrator.totalLocked(), 0);
        assertEq(escrowMigrator.totalEscrowUnmigrated(user1), 0);
        assertEq(escrowMigrator.totalEscrowUnmigrated(user2), 0);
        assertEq(
            escrowMigrator.totalEscrowUnmigrated(user3), escrowMigrator.totalEscrowRegistered(user3)
        );
    }

    function test_User_Regisered_Free_Frozen_Funds() public {
        vm.prank(user1);
        stakingRewardsV1.getReward();
        vm.prank(user2);
        stakingRewardsV1.getReward();
        vm.prank(user3);
        stakingRewardsV1.getReward();

        (, uint256 user1Fee) = rewardEscrowV1.getVestingQuantity(user1, getEntryIDs(user1));
        (uint256 user3Total, uint256 user3Fee) =
            rewardEscrowV1.getVestingQuantity(user3, getEntryIDs(user3));

        vest(user1);
        claimAndFullyMigrate(user2);
        claimAndRegisterEntries(user3);

        vm.warp(block.timestamp + escrowMigrator.MIGRATION_DEADLINE() + 1);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        escrowMigrator.updateTotalLocked(users);
        assertEq(escrowMigrator.totalLocked(), escrowMigrator.totalEscrowRegistered(user3));

        uint256 balanceBefore = kwenta.balanceOf(treasury);

        // recover the funds
        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();

        uint256 balanceAfter = kwenta.balanceOf(treasury);
        uint256 recoveredFunds = balanceAfter - balanceBefore;
        assertEq(recoveredFunds, user1Fee - user3Total - user3Fee + escrowMigrator.totalLocked());
        assertEq(kwenta.balanceOf(address(escrowMigrator)), 0);
        assertEq(escrowMigrator.totalEscrowUnmigrated(user1), 0);
        assertEq(escrowMigrator.totalEscrowUnmigrated(user2), 0);
        assertEq(escrowMigrator.totalEscrowUnmigrated(user3), escrowMigrator.totalLocked());

        // does not allow further withdrawal of funds
        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();
        assertEq(kwenta.balanceOf(treasury), balanceAfter);
    }

    function test_Cannot_Duplicate_Freeze_Funds() public {
        vm.prank(user1);
        stakingRewardsV1.getReward();
        vm.prank(user2);
        stakingRewardsV1.getReward();
        vm.prank(user3);
        stakingRewardsV1.getReward();

        (, uint256 user1Fee) = rewardEscrowV1.getVestingQuantity(user1, getEntryIDs(user1));
        (uint256 user3Total, uint256 user3Fee) =
            rewardEscrowV1.getVestingQuantity(user3, getEntryIDs(user3));

        vest(user1);
        claimAndFullyMigrate(user2);
        claimAndRegisterEntries(user3);

        vm.warp(block.timestamp + escrowMigrator.MIGRATION_DEADLINE() + 1);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        escrowMigrator.updateTotalLocked(users);
        escrowMigrator.updateTotalLocked(users);
        escrowMigrator.updateTotalLocked(users);
        assertEq(escrowMigrator.totalLocked(), escrowMigrator.totalEscrowRegistered(user3));

        uint256 balanceBefore = kwenta.balanceOf(treasury);

        // recover the funds
        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();

        uint256 balanceAfter = kwenta.balanceOf(treasury);
        uint256 recoveredFunds = balanceAfter - balanceBefore;
        assertEq(recoveredFunds, user1Fee - user3Total - user3Fee + escrowMigrator.totalLocked());
        assertEq(kwenta.balanceOf(address(escrowMigrator)), 0);

        // does not allow further withdrawal of funds
        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();
        assertEq(kwenta.balanceOf(treasury), balanceAfter);
    }

    function test_User_Regisered_Free_Frozen_Funds_No_List() public {
        claimAndRegisterEntries(user1);
        claimAndRegisterEntries(user2);
        claimAndRegisterEntries(user3);

        vm.warp(block.timestamp + escrowMigrator.MIGRATION_DEADLINE() + 1);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        escrowMigrator.updateTotalLocked(user1);
        escrowMigrator.updateTotalLocked(user2);
        escrowMigrator.updateTotalLocked(user3);

        assertEq(escrowMigrator.totalLocked(), escrowMigrator.totalRegistered());
        assertEq(
            escrowMigrator.totalEscrowUnmigrated(user1), escrowMigrator.totalEscrowRegistered(user1)
        );
        assertEq(
            escrowMigrator.totalEscrowUnmigrated(user2), escrowMigrator.totalEscrowRegistered(user2)
        );
        assertEq(
            escrowMigrator.totalEscrowUnmigrated(user3), escrowMigrator.totalEscrowRegistered(user3)
        );
    }

    function test_Fund_Recovery_User_Registered_And_Vested() public {
        vm.prank(user1);
        stakingRewardsV1.getReward();
        vm.prank(user2);
        stakingRewardsV1.getReward();
        vm.prank(user3);
        stakingRewardsV1.getReward();

        uint256 userBalanceBeforeVest = kwenta.balanceOf(user1);
        uint256 escrowMigratorBalanceBeforeVest = kwenta.balanceOf(address(escrowMigrator));

        uint256[] memory _entryIDs = getEntryIDs(user1);
        (uint256 total, uint256 fee) = rewardEscrowV1.getVestingQuantity(user1, _entryIDs);
        (uint256 user2Total, uint256 user2Fee) =
            rewardEscrowV1.getVestingQuantity(user2, getEntryIDs(user2));
        (uint256 user3Total, uint256 user3Fee) =
            rewardEscrowV1.getVestingQuantity(user3, getEntryIDs(user3));

        vest(user1);

        assertEq(escrowMigrator.totalRegistered(), 0);
        assertEq(escrowMigrator.totalMigrated(), 0);
        assertEq(kwenta.balanceOf(address(escrowMigrator)), fee);
        assertEq(kwenta.balanceOf(user1) - userBalanceBeforeVest, total);
        assertEq(kwenta.balanceOf(address(escrowMigrator)) - escrowMigratorBalanceBeforeVest, fee);

        claimAndFullyMigrate(user2);
        claimRegisterAndVestEntries(user3);

        assertEq(
            escrowMigrator.totalRegistered(),
            escrowMigrator.totalEscrowRegistered(user2)
                + escrowMigrator.totalEscrowRegistered(user3)
        );
        assertEq(
            escrowMigrator.totalEscrowRegistered(user2), rewardEscrowV2.escrowedBalanceOf(user2)
        );
        assertEq(escrowMigrator.totalEscrowRegistered(user2), user2Total + user2Fee);
        assertEq(escrowMigrator.totalEscrowRegistered(user3), user3Total + user3Fee);
        assertEq(escrowMigrator.totalMigrated(), escrowMigrator.totalEscrowRegistered(user2));
        assertEq(escrowMigrator.totalMigrated(), user2Total + user2Fee);
        assertEq(kwenta.balanceOf(address(escrowMigrator)), fee + user3Fee);
        assertEq(
            kwenta.balanceOf(address(escrowMigrator)) - escrowMigratorBalanceBeforeVest,
            fee + user3Fee
        );

        uint256 balanceBefore = kwenta.balanceOf(treasury);

        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();

        uint256 balanceAfter = kwenta.balanceOf(treasury);

        assertEq(balanceAfter - balanceBefore, fee - user3Total);
        assertEq(kwenta.balanceOf(address(escrowMigrator)), user3Total + user3Fee);

        approveAndMigrate(user3);
        checkStateAfterStepThree(user3, 1, 12);
    }

    function test_User_Registered_And_Vested_Cannot_Free_Frozen_Funds_If_Deadline_Not_Passed()
        public
    {
        vest(user1);
        claimAndFullyMigrate(user2);
        claimRegisterAndVestEntries(user3);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        escrowMigrator.updateTotalLocked(users);

        assertEq(escrowMigrator.totalLocked(), 0);
    }

    function test_User_Regisered_And_Vested_Free_Frozen_Funds() public {
        vm.prank(user1);
        stakingRewardsV1.getReward();
        vm.prank(user2);
        stakingRewardsV1.getReward();
        vm.prank(user3);
        stakingRewardsV1.getReward();

        (, uint256 user1Fee) = rewardEscrowV1.getVestingQuantity(user1, getEntryIDs(user1));
        (uint256 user3Total,) = rewardEscrowV1.getVestingQuantity(user3, getEntryIDs(user3));

        vest(user1);
        claimAndFullyMigrate(user2);
        claimRegisterAndVestEntries(user3);

        vm.warp(block.timestamp + escrowMigrator.MIGRATION_DEADLINE() + 1);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        escrowMigrator.updateTotalLocked(users);
        assertEq(escrowMigrator.totalLocked(), escrowMigrator.totalEscrowRegistered(user3));

        uint256 balanceBefore = kwenta.balanceOf(treasury);

        // recover the funds
        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();

        uint256 balanceAfter = kwenta.balanceOf(treasury);
        uint256 recoveredFunds = balanceAfter - balanceBefore;

        assertEq(recoveredFunds, user1Fee - user3Total + escrowMigrator.totalLocked());
        assertEq(kwenta.balanceOf(address(escrowMigrator)), 0);

        // does not allow further withdrawal of funds
        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();
        assertEq(kwenta.balanceOf(treasury), balanceAfter);
    }

    function test_Fund_Recovery_User_Migrated() public {
        uint256 userBalanceBeforeVest = kwenta.balanceOf(user1);
        uint256 escrowMigratorBalanceBeforeVest = kwenta.balanceOf(address(escrowMigrator));

        uint256[] memory _entryIDs = getEntryIDs(user1);
        (uint256 total, uint256 fee) = rewardEscrowV1.getVestingQuantity(user1, _entryIDs);

        vest(user1);

        assertEq(escrowMigrator.totalRegistered(), 0);
        assertEq(escrowMigrator.totalMigrated(), 0);
        assertEq(kwenta.balanceOf(address(escrowMigrator)), fee);
        assertEq(kwenta.balanceOf(user1) - userBalanceBeforeVest, total);
        assertEq(kwenta.balanceOf(address(escrowMigrator)) - escrowMigratorBalanceBeforeVest, fee);

        claimAndFullyMigrate(user2);

        assertEq(escrowMigrator.totalRegistered(), rewardEscrowV2.escrowedBalanceOf(user2));
        assertEq(escrowMigrator.totalMigrated(), escrowMigrator.totalRegistered());
        assertEq(kwenta.balanceOf(address(escrowMigrator)), fee);
        assertEq(kwenta.balanceOf(address(escrowMigrator)) - escrowMigratorBalanceBeforeVest, fee);

        uint256 balanceBefore = kwenta.balanceOf(treasury);

        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();

        assertEq(kwenta.balanceOf(address(escrowMigrator)), 0);
        assertEq(kwenta.balanceOf(treasury) - balanceBefore, fee);

        claimAndFullyMigrate(user3);
        checkStateAfterStepThree(user2);
        checkStateAfterStepThree(user3, 1, 12);
    }

    function test_User_Migrated_Cannot_Free_Frozen_Funds_If_Deadline_Not_Passed() public {
        vest(user1);
        claimAndFullyMigrate(user2);
        claimAndFullyMigrate(user3);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        escrowMigrator.updateTotalLocked(users);

        assertEq(escrowMigrator.totalLocked(), 0);
    }

    function test_User_Migrated_Free_Frozen_Funds() public {
        vm.prank(user1);
        stakingRewardsV1.getReward();
        vm.prank(user2);
        stakingRewardsV1.getReward();
        vm.prank(user3);
        stakingRewardsV1.getReward();

        (, uint256 user1Fee) = rewardEscrowV1.getVestingQuantity(user1, getEntryIDs(user1));

        vest(user1);
        claimAndFullyMigrate(user2);
        claimAndFullyMigrate(user3);

        vm.warp(block.timestamp + escrowMigrator.MIGRATION_DEADLINE() + 1);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        escrowMigrator.updateTotalLocked(users);
        assertEq(escrowMigrator.totalLocked(), 0);

        uint256 balanceBefore = kwenta.balanceOf(treasury);

        // recover the funds
        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();

        uint256 balanceAfter = kwenta.balanceOf(treasury);
        uint256 recoveredFunds = balanceAfter - balanceBefore;

        assertEq(recoveredFunds, user1Fee + escrowMigrator.totalLocked());
        assertEq(kwenta.balanceOf(address(escrowMigrator)), 0);

        // does not allow further withdrawal of funds
        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();
        assertEq(kwenta.balanceOf(treasury), balanceAfter);
    }

    function test_User_Semi_Migrated_Free_Frozen_Funds() public {
        vm.prank(user1);
        stakingRewardsV1.getReward();
        vm.prank(user2);
        stakingRewardsV1.getReward();
        vm.prank(user3);
        stakingRewardsV1.getReward();

        (, uint256 user1Fee) = rewardEscrowV1.getVestingQuantity(user1, getEntryIDs(user1));
        (uint256 user2TotalMigrated, uint256 user2FeeMigrated) =
            rewardEscrowV1.getVestingQuantity(user2, getEntryIDs(user2, 0, 10));
        (uint256 user2Total, uint256 user2Fee) =
            rewardEscrowV1.getVestingQuantity(user2, getEntryIDs(user2));

        vest(user1);
        // user2 has 37 entries
        claimAndRegisterEntries(user2);
        vestApproveAndMigrate(user2, 0, 10);
        claimAndFullyMigrate(user3);

        vm.warp(block.timestamp + escrowMigrator.MIGRATION_DEADLINE() + 1);

        escrowMigrator.updateTotalLocked(user2);
        assertEq(
            escrowMigrator.totalLocked(),
            user2Total + user2Fee - user2TotalMigrated - user2FeeMigrated
        );

        uint256 balanceBefore = kwenta.balanceOf(treasury);

        // recover the funds
        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();

        uint256 balanceAfter = kwenta.balanceOf(treasury);
        uint256 recoveredFunds = balanceAfter - balanceBefore;

        assertEq(recoveredFunds, user1Fee);
        assertEq(kwenta.balanceOf(address(escrowMigrator)), 0);

        // does not allow further withdrawal of funds
        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();
        assertEq(kwenta.balanceOf(treasury), balanceAfter);
    }

    function test_User_Semi_Migrated_And_Fully_Vested_Free_Frozen_Funds() public {
        vm.prank(user1);
        stakingRewardsV1.getReward();
        vm.prank(user2);
        stakingRewardsV1.getReward();
        vm.prank(user3);
        stakingRewardsV1.getReward();

        (, uint256 user1Fee) = rewardEscrowV1.getVestingQuantity(user1, getEntryIDs(user1));
        (uint256 user2TotalMigrated, uint256 user2FeeMigrated) =
            rewardEscrowV1.getVestingQuantity(user2, getEntryIDs(user2, 0, 10));
        (uint256 user2Total, uint256 user2Fee) =
            rewardEscrowV1.getVestingQuantity(user2, getEntryIDs(user2));

        vest(user1);
        // user2 has 37 entries
        claimRegisterVestAndApprove(user2);
        approveAndMigrate(user2, 0, 10);
        claimAndFullyMigrate(user3);

        vm.warp(block.timestamp + escrowMigrator.MIGRATION_DEADLINE() + 1);

        escrowMigrator.updateTotalLocked(user2);
        assertEq(
            escrowMigrator.totalLocked(),
            user2Total + user2Fee - user2TotalMigrated - user2FeeMigrated
        );

        uint256 balanceBefore = kwenta.balanceOf(treasury);

        // recover the funds
        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();

        uint256 balanceAfter = kwenta.balanceOf(treasury);
        uint256 recoveredFunds = balanceAfter - balanceBefore;

        assertEq(recoveredFunds, user1Fee + escrowMigrator.totalLocked());
        assertEq(kwenta.balanceOf(address(escrowMigrator)), 0);

        // does not allow further withdrawal of funds
        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();
        assertEq(kwenta.balanceOf(treasury), balanceAfter);
    }

    /*//////////////////////////////////////////////////////////////
                               GAS TESTS
    //////////////////////////////////////////////////////////////*/

    // function test_Max_Registerable_In_One_Go() public {
    //     uint256 numInRound = 1500;
    //     console.log("num in round:", numInRound);

    //     address botUser = OPTIMISM_RANDOM_STAKING_BOT_USER_1;
    //     claimAndCheckInitialState(botUser);
    //     uint256[] memory _entryIDs = getEntryIDs(botUser, 0, numInRound);

    //     startMeasuringGas("registering entries");
    //     registerEntries(botUser, _entryIDs);
    //     uint256 gasDelta = stopMeasuringGas() + 21_000;
    //     assertLe(gasDelta, 15_000_000);

    //     vestAndApprove(botUser, 0, numInRound);

    //     startMeasuringGas("migrating entries");
    //     migrateEntries(botUser, _entryIDs);
    //     gasDelta = stopMeasuringGas() + 21_000;
    //     assertLe(gasDelta, 15_000_000);
    // }
}
