// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "./StakingTestHelpers.t.sol";
import {Migrate} from "../../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../../contracts/RewardEscrow.sol";
import {VestingEntries} from "../../../../contracts/interfaces/IRewardEscrow.sol";
import {IEscrowMigrator} from "../../../../contracts/interfaces/IEscrowMigrator.sol";
import {SupplySchedule} from "../../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../../contracts/StakingRewards.sol";
import {EscrowMigrator} from "../../../../contracts/EscrowMigrator.sol";
import "../../utils/Constants.t.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract EscrowMigratorTestHelpers is StakingTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public owner;
    EscrowMigrator public escrowMigrator;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        vm.rollFork(106_878_447);

        // define main contracts
        kwenta = Kwenta(OPTIMISM_KWENTA_TOKEN);
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

        // set owners address code to trick the test into allowing onlyOwner functions to be called via script
        vm.etch(owner, address(new Migrate()).code);

        (rewardEscrowV2, stakingRewardsV2,,) = Migrate(owner).runCompleteMigrationProcess({
            _owner: owner,
            _kwenta: address(kwenta),
            _supplySchedule: address(supplySchedule),
            _treasuryDAO: treasury,
            _printLogs: false
        });

        // deploy migrator
        address migratorImpl = address(
            new EscrowMigrator(
            address(kwenta),
            address(rewardEscrowV1),
            address(rewardEscrowV2),
            address(stakingRewardsV1),
            address(stakingRewardsV2)
            )
        );

        escrowMigrator = EscrowMigrator(
            address(
                new ERC1967Proxy(
                    migratorImpl,
                    abi.encodeWithSignature("initialize(address)", owner)
                )
            )
        );

        vm.prank(owner);
        rewardEscrowV2.setEscrowMigrator(address(escrowMigrator));

        vm.prank(owner);
        rewardEscrowV1.setTreasuryDAO(address(escrowMigrator));
    }

    /*//////////////////////////////////////////////////////////////
                             STEP 1 HELPERS
    //////////////////////////////////////////////////////////////*/

    function claimAndCheckInitialState(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries)
    {
        // claim rewards
        getStakingRewardsV1(account);
        return checkStateBeforeStepOne(account);
    }

    function checkStateBeforeStepOne(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries)
    {
        uint256 v2BalanceBefore = rewardEscrowV2.escrowedBalanceOf(account);
        uint256 v1BalanceBefore = rewardEscrowV1.balanceOf(account);
        assertGt(v1BalanceBefore, 0);
        assertEq(v2BalanceBefore, 0);

        numVestingEntries = rewardEscrowV1.numVestingEntries(account);
        assertGt(numVestingEntries, 0);

        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(account, 0, numVestingEntries);
        assertEq(_entryIDs.length, numVestingEntries);

        assertEq(uint256(escrowMigrator.migrationStatus(account)), 0);
        assertEq(escrowMigrator.escrowVestedAtStart(account), 0);
        assertEq(escrowMigrator.numberOfConfirmedEntries(account), 0);
        assertEq(escrowMigrator.numberOfMigratedEntries(account), 0);
        assertEq(escrowMigrator.numberOfRegisteredEntries(account), 0);
        assertEq(escrowMigrator.toPayForMigration(account), 0);

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            (uint256 escrowAmount, uint256 duration, uint64 endTime, bool confirmed, bool migrated)
            = escrowMigrator.registeredVestingSchedules(account, entryID);
            assertEq(escrowAmount, 0);
            assertEq(duration, 0);
            assertEq(endTime, 0);
            assertEq(confirmed, false);
            assertEq(migrated, false);
        }
    }

    function checkStateAfterStepOne(address account, uint256[] memory _entryIDs, bool didRegister)
        internal
    {
        if (!didRegister && _entryIDs.length == 0) {
            // didn't register
            assertEq(uint256(escrowMigrator.migrationStatus(account)), 0);
        } else if (_entryIDs.length == 0) {
            // initiated but didn't register any entries
            assertEq(uint256(escrowMigrator.migrationStatus(account)), 1);
        } else {
            // initiated and registerd entries
            assertEq(uint256(escrowMigrator.migrationStatus(account)), 2);
        }

        assertEq(
            escrowMigrator.escrowVestedAtStart(account),
            rewardEscrowV1.totalVestedAccountBalance(account)
        );
        assertEq(escrowMigrator.numberOfRegisteredEntries(account), _entryIDs.length);
        assertEq(escrowMigrator.numberOfConfirmedEntries(account), 0);
        assertEq(escrowMigrator.numberOfMigratedEntries(account), 0);
        assertEq(escrowMigrator.toPayForMigration(account), 0);

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            assertEq(escrowMigrator.registeredEntryIDs(account, i), entryID);
            (uint256 escrowAmount, uint256 duration, uint64 endTime, bool confirmed, bool migrated)
            = escrowMigrator.registeredVestingSchedules(account, entryID);
            (uint64 endTimeOriginal, uint256 escrowAmountOriginal, uint256 durationOriginal) =
                rewardEscrowV1.getVestingEntry(account, entryID);
            assertEq(escrowAmount, escrowAmountOriginal);
            assertEq(duration, durationOriginal);
            assertEq(endTime, endTimeOriginal);
            assertEq(confirmed, false);
            assertEq(migrated, false);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             STEP 2 HELPERS
    //////////////////////////////////////////////////////////////*/

    function registerEntries(address account, uint256[] memory _entryIDs) internal {
        // check initial state
        claimAndCheckInitialState(account);

        // step 1
        vm.prank(account);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
    }

    function registerAndVestEntries(address account, uint256[] memory _entryIDs) internal {
        registerEntries(account, _entryIDs);

        // step 2.1 - vest
        vm.prank(account);
        rewardEscrowV1.vest(_entryIDs);
    }

    function registerAllEntries(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries)
    {
        // check initial state
        (_entryIDs, numVestingEntries) = claimAndCheckInitialState(account);

        // step 1
        vm.prank(account);
        escrowMigrator.registerEntriesForVestingAndMigration(_entryIDs);
    }

    function registerAndVestAllEntries(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries)
    {
        (_entryIDs, numVestingEntries) = registerAllEntries(account);

        // step 2.1 - vest
        vm.prank(account);
        rewardEscrowV1.vest(_entryIDs);
    }

    function checkStateAfterStepTwo(address account, uint256[] memory _entryIDs, bool confirmedAll)
        internal
    {
        if (confirmedAll) {
            assertEq(uint256(escrowMigrator.migrationStatus(account)), 3);
        } else {
            assertEq(uint256(escrowMigrator.migrationStatus(account)), 2);
        }

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            assertEq(escrowMigrator.registeredEntryIDs(account, i), entryID);
            (uint256 escrowAmount, uint256 duration, uint64 endTime, bool confirmed, bool migrated)
            = escrowMigrator.registeredVestingSchedules(account, entryID);
            (uint64 endTimeOriginal, uint256 escrowAmountOriginal, uint256 durationOriginal) =
                rewardEscrowV1.getVestingEntry(account, entryID);
            assertGt(escrowAmount, 0);
            assertEq(escrowAmountOriginal, 0);
            assertEq(duration, durationOriginal);
            assertEq(endTime, endTimeOriginal);
            assertEq(confirmed, true);
            assertEq(migrated, false);
        }

        assertLe(_entryIDs.length, escrowMigrator.numberOfRegisteredEntries(account));
        if (entryIDs.length > 0) {
            assertLt(
                escrowMigrator.escrowVestedAtStart(account),
                rewardEscrowV1.totalVestedAccountBalance(account)
            );
        } else {
            assertLe(
                escrowMigrator.escrowVestedAtStart(account),
                rewardEscrowV1.totalVestedAccountBalance(account)
            );
        }

        assertEq(escrowMigrator.numberOfConfirmedEntries(account), _entryIDs.length);
        assertEq(escrowMigrator.numberOfMigratedEntries(account), 0);
        if (confirmedAll) {
            assertEq(
                escrowMigrator.numberOfConfirmedEntries(account),
                escrowMigrator.numberOfRegisteredEntries(account)
            );
            assertEq(escrowMigrator.numberOfRegisteredEntries(account), _entryIDs.length);
            assertEq(
                escrowMigrator.toPayForMigration(account),
                rewardEscrowV1.totalVestedAccountBalance(account)
                    - escrowMigrator.escrowVestedAtStart(account)
            );
        } else {
            assertEq(escrowMigrator.toPayForMigration(account), 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                             STEP 3 HELPERS
    //////////////////////////////////////////////////////////////*/

    function fullyMigrateAllEntries(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries, uint256 toPay)
    {
        // register and vest
        (_entryIDs, numVestingEntries, toPay) = registerVestConfirmAllEntriesAndApprove(account);

        vm.prank(account);
        escrowMigrator.migrateConfirmedEntries(account, _entryIDs);
    }

    function registerVestAndConfirmEntries(address account, uint256[] memory _entryIDs) internal {
        registerAndVestEntries(account, _entryIDs);

        vm.prank(account);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);
    }

    function registerVestConfirmAndApproveEntries(address account, uint256[] memory _entryIDs)
        internal
    {
        registerAndVestEntries(account, _entryIDs);

        vm.prank(account);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);

        uint256 toPay = escrowMigrator.toPayForMigration(account);

        vm.prank(account);
        kwenta.approve(address(escrowMigrator), toPay);
    }

    function registerVestAndConfirmAllEntries(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries, uint256 toPay)
    {
        // register and vest
        (_entryIDs, numVestingEntries) = registerAndVestAllEntries(account);

        vm.prank(account);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);

        toPay = escrowMigrator.toPayForMigration(account);
    }

    function registerVestConfirmAllEntriesAndApprove(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries, uint256 toPay)
    {
        // register and vest
        (_entryIDs, numVestingEntries) = registerAndVestAllEntries(account);

        vm.prank(account);
        escrowMigrator.confirmEntriesAreVested(_entryIDs);

        toPay = escrowMigrator.toPayForMigration(account);

        vm.prank(account);
        kwenta.approve(address(escrowMigrator), toPay);
    }

    function moveToPaidState(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries)
    {
        // register, vest and confirm
        (_entryIDs, numVestingEntries,) = registerVestAndConfirmAllEntries(account);

        // migrate with 0 entries
        vm.prank(account);
        kwenta.approve(address(escrowMigrator), type(uint256).max);
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(account, 0, 0);
        vm.prank(account);
        escrowMigrator.migrateConfirmedEntries(account, _entryIDs);

        // restore entryIDs
        _entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(account, 0, numVestingEntries);
    }

    function moveToCompletedState(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries)
    {
        // register, vest and confirm
        (_entryIDs, numVestingEntries,) = registerVestAndConfirmAllEntries(account);

        // migrate with all entries
        vm.prank(account);
        kwenta.approve(address(escrowMigrator), type(uint256).max);
        vm.prank(account);
        escrowMigrator.migrateConfirmedEntries(account, _entryIDs);
    }

    function checkStateAfterStepThree(address account, uint256[] memory _entryIDs, bool paid)
        internal
    {
        uint256 numOfV2Entries = rewardEscrowV2.balanceOf(account);
        uint256[] memory migratedEntries =
            rewardEscrowV2.getAccountVestingEntryIDs(account, 0, numOfV2Entries);
        assertEq(numOfV2Entries, _entryIDs.length);

        uint256 totalEscrowMigrated;
        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            uint256 migratedEntryID = migratedEntries[i];
            checkMigratedEntryAfterStepThree(account, migratedEntryID, entryID);
            (uint256 escrowAmount,,,,) = checkEntryAfterStepThree(account, i, entryID);
            totalEscrowMigrated += escrowAmount;
        }

        checkStateAfterStepThreeAssertions(account, _entryIDs, paid, totalEscrowMigrated);
    }

    // TODO: finish this function
    function checkMigratedEntryAfterStepThree(
        address account,
        uint256 newEntryID,
        uint256 oldEntryID
    ) internal {
        (uint64 endTime, uint256 escrowAmount, uint256 duration, uint8 earlyVestingFee) =
            rewardEscrowV2.getVestingEntry(newEntryID);

        (uint256 registeredEscrowAmount, uint256 registeredDuration, uint64 registeredEndTime,,) =
            escrowMigrator.registeredVestingSchedules(account, oldEntryID);

        assertEq(earlyVestingFee, 90);
        assertEq(escrowAmount, registeredEscrowAmount);
        uint256 cooldown = stakingRewardsV2.cooldownPeriod();
        if (registeredDuration < cooldown) {
            assertEq(duration, cooldown);
            assertEq(endTime, registeredEndTime - registeredDuration + cooldown);
        } else {
            assertEq(duration, registeredDuration);
            assertEq(endTime, registeredEndTime);
        }
    }

    function checkEntryAfterStepThree(address account, uint256 i, uint256 entryID)
        internal
        returns (
            uint256 escrowAmount,
            uint256 duration,
            uint64 endTime,
            bool confirmed,
            bool migrated
        )
    {
        assertEq(escrowMigrator.registeredEntryIDs(account, i), entryID);

        (escrowAmount, duration, endTime, confirmed, migrated) =
            escrowMigrator.registeredVestingSchedules(account, entryID);
        (uint64 endTimeOriginal, uint256 escrowAmountOriginal, uint256 durationOriginal) =
            rewardEscrowV1.getVestingEntry(account, entryID);

        assertGt(escrowAmount, 0);
        assertEq(escrowAmountOriginal, 0);
        assertEq(duration, durationOriginal);
        assertEq(endTime, endTimeOriginal);
        assertEq(confirmed, true);
        assertEq(migrated, true);
    }

    function checkStateAfterStepThreeAssertions(
        address account,
        uint256[] memory _entryIDs,
        bool paid,
        uint256 totalEscrowMigrated
    ) internal {
        bool completed = escrowMigrator.numberOfRegisteredEntries(account) == _entryIDs.length;
        if (completed) {
            assertEq(uint256(escrowMigrator.migrationStatus(account)), 5);
        } else if (paid) {
            assertEq(uint256(escrowMigrator.migrationStatus(account)), 4);
        } else {
            assertEq(uint256(escrowMigrator.migrationStatus(account)), 3);
        }

        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(account), totalEscrowMigrated);
        assertLe(_entryIDs.length, escrowMigrator.numberOfRegisteredEntries(account));
        assertLt(
            escrowMigrator.escrowVestedAtStart(account),
            rewardEscrowV1.totalVestedAccountBalance(account)
        );
        assertEq(escrowMigrator.numberOfMigratedEntries(account), _entryIDs.length);
        assertEq(
            escrowMigrator.numberOfConfirmedEntries(account),
            escrowMigrator.numberOfRegisteredEntries(account)
        );
        assertLe(
            escrowMigrator.toPayForMigration(account),
            rewardEscrowV1.totalVestedAccountBalance(account)
                - escrowMigrator.escrowVestedAtStart(account)
        );
        if (completed) {
            assertEq(
                escrowMigrator.numberOfMigratedEntries(account),
                escrowMigrator.numberOfConfirmedEntries(account)
            );
            assertEq(escrowMigrator.numberOfConfirmedEntries(account), _entryIDs.length);
            assertEq(escrowMigrator.numberOfRegisteredEntries(account), _entryIDs.length);
        } else {
            assertLt(
                escrowMigrator.numberOfMigratedEntries(account),
                escrowMigrator.numberOfConfirmedEntries(account)
            );
            assertGt(escrowMigrator.numberOfConfirmedEntries(account), _entryIDs.length);
        }
    }
}
