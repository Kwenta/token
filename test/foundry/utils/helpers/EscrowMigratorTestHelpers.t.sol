// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "./StakingTestHelpers.t.sol";
import {Migrate} from "../../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../../contracts/RewardEscrow.sol";
import {VestingEntries} from "../../../../contracts/interfaces/IRewardEscrow.sol";
import {IEscrowMigrator} from "../../../../contracts/interfaces/IEscrowMigrator.sol";
import {IStakingRewardsIntegrator} from
    "../../../../contracts/interfaces/IStakingRewardsIntegrator.sol";
import {SupplySchedule} from "../../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../../contracts/StakingRewards.sol";
import {EscrowMigrator} from "../../../../contracts/EscrowMigrator.sol";
import "../../utils/Constants.t.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract EscrowMigratorTestHelpers is StakingTestHelpers {
    /*//////////////////////////////////////////////////////////////
                            GENERIC HELPERS
    //////////////////////////////////////////////////////////////*/

    function getEntryIDs(address account) internal view returns (uint256[] memory) {
        uint256 numVestingEntries = rewardEscrowV1.numVestingEntries(account);
        return rewardEscrowV1.getAccountVestingEntryIDs(account, 0, numVestingEntries);
    }

    function getEntryIDs(address account, uint256 index, uint256 amount)
        internal
        view
        returns (uint256[] memory)
    {
        return rewardEscrowV1.getAccountVestingEntryIDs(account, index, amount);
    }

    /*//////////////////////////////////////////////////////////////
                            COMMAND HELPERS
    //////////////////////////////////////////////////////////////*/

    function approveAndMigrate(address account) internal {
        uint256[] memory _entryIDs = getEntryIDs(account);
        approveAndMigrate(account, _entryIDs);
    }

    function approveAndMigrate(address account, uint256 index, uint256 amount) internal {
        uint256[] memory _entryIDs = getEntryIDs(account, index, amount);
        approveAndMigrate(account, _entryIDs);
    }

    function approveAndMigrate(address account, uint256[] memory _entryIDs) internal {
        approve(account);
        migrateEntries(account, _entryIDs);
    }

    function approve(address account) internal returns (uint256 toPay) {
        toPay = escrowMigrator.toPay(account);
        vm.prank(account);
        kwenta.approve(address(escrowMigrator), type(uint256).max);
    }

    function migrateEntries(address account) internal returns (uint256[] memory _entryIDs) {
        _entryIDs = getEntryIDs(account);
        migrateEntries(account, _entryIDs);
    }

    function migrateEntries(address account, uint256 index, uint256 amount)
        internal
        returns (uint256[] memory _entryIDs)
    {
        _entryIDs = getEntryIDs(account, index, amount);
        migrateEntries(account, _entryIDs);
    }

    function migrateEntries(address account, uint256[] memory _entryIDs)
        internal
        returns (uint256[] memory)
    {
        vm.prank(account);
        escrowMigrator.migrateEntries(account, _entryIDs);
        return _entryIDs;
    }

    function vest(address account) internal {
        uint256[] memory _entryIDs = getEntryIDs(account);
        vest(account, _entryIDs);
    }

    function vest(address account, uint256 index, uint256 amount) internal {
        uint256[] memory _entryIDs = getEntryIDs(account, index, amount);
        vest(account, _entryIDs);
    }

    function vest(address account, uint256[] memory _entryIDs) internal {
        vm.prank(account);
        rewardEscrowV1.vest(_entryIDs);
    }

    function vestApproveAndMigrate(address account, uint256 index, uint256 amount) internal {
        vestAndApprove(account, index, amount);
        migrateEntries(account, index, amount);
    }

    function vestApproveAndMigrate(address account) internal {
        vestAndApprove(account);
        migrateEntries(account);
    }

    function vestAndApprove(address account) internal {
        uint256[] memory _entryIDs = getEntryIDs(account);
        vestAndApprove(account, _entryIDs);
    }

    function vestAndApprove(address account, uint256 index, uint256 amount) internal {
        vest(account, index, amount);
        approve(account);
    }

    function vestAndApprove(address account, uint256[] memory _entryIDs) internal {
        vest(account, _entryIDs);
        approve(account);
    }

    function registerEntries(address account) internal returns (uint256[] memory _entryIDs) {
        _entryIDs = getEntryIDs(account);
        registerEntries(account, _entryIDs);
    }

    function registerEntries(address account, uint256 index, uint256 amount)
        internal
        returns (uint256[] memory _entryIDs)
    {
        _entryIDs = getEntryIDs(account, index, amount);
        registerEntries(account, _entryIDs);
    }

    function registerEntries(address account, uint256[] memory _entryIDs) internal {
        vm.prank(account);
        escrowMigrator.registerEntries(_entryIDs);
    }

    function registerAndVestEntries(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries)
    {
        _entryIDs = getEntryIDs(account);
        return registerAndVestEntries(account, _entryIDs);
    }

    function registerAndVestEntries(address account, uint256 index, uint256 amount)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries)
    {
        _entryIDs = getEntryIDs(account, index, amount);
        return registerAndVestEntries(account, _entryIDs);
    }

    function registerAndVestEntries(address account, uint256[] memory _entryIDs)
        internal
        returns (uint256[] memory, uint256 numVestingEntries)
    {
        vm.prank(account);
        escrowMigrator.registerEntries(_entryIDs);
        vest(account, _entryIDs);
        return (_entryIDs, _entryIDs.length);
    }

    function registerVestAndApprove(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries, uint256 toPay)
    {
        _entryIDs = getEntryIDs(account);
        return registerVestAndApprove(account, _entryIDs);
    }

    function registerVestAndApprove(address account, uint256 index, uint256 amount)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries, uint256 toPay)
    {
        _entryIDs = getEntryIDs(account, index, amount);
        return registerVestAndApprove(account, _entryIDs);
    }

    function registerVestAndApprove(address account, uint256[] memory _entryIDs)
        internal
        returns (uint256[] memory, uint256 numVestingEntries, uint256 toPay)
    {
        (, numVestingEntries) = registerAndVestEntries(account, _entryIDs);
        toPay = approve(account);
        return (_entryIDs, numVestingEntries, toPay);
    }

    function claimAndRegisterEntries(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries)
    {
        // check initial state
        claimAndCheckInitialState(account);

        _entryIDs = getEntryIDs(account);
        numVestingEntries = _entryIDs.length;

        // step 1
        vm.prank(account);
        escrowMigrator.registerEntries(_entryIDs);
    }

    function claimAndRegisterEntries(address account, uint256 index, uint256 amount)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries)
    {
        // check initial state
        claimAndCheckInitialState(account);

        _entryIDs = getEntryIDs(account, index, amount);
        numVestingEntries = _entryIDs.length;

        // step 1
        vm.prank(account);
        escrowMigrator.registerEntries(_entryIDs);
    }

    function claimAndRegisterEntries(address account, uint256[] memory _entryIDs)
        internal
        returns (uint256[] memory, uint256 numVestingEntries)
    {
        // check initial state
        claimAndCheckInitialState(account);

        // step 1
        vm.prank(account);
        escrowMigrator.registerEntries(_entryIDs);

        return (_entryIDs, _entryIDs.length);
    }

    function claimRegisterAndVestEntries(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries)
    {
        claimAndCheckInitialState(account);
        _entryIDs = getEntryIDs(account);
        numVestingEntries = _entryIDs.length;
        claimRegisterAndVestEntries(account, _entryIDs);
    }

    function claimRegisterAndVestEntries(address account, uint256 index, uint256 amount)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries)
    {
        claimAndCheckInitialState(account);
        _entryIDs = getEntryIDs(account, index, amount);
        numVestingEntries = _entryIDs.length;
        claimRegisterAndVestEntries(account, _entryIDs);
    }

    function claimRegisterAndVestEntries(address account, uint256[] memory _entryIDs)
        internal
        returns (uint256[] memory, uint256)
    {
        claimAndRegisterEntries(account, _entryIDs);

        // step 2.1 - vest
        vm.prank(account);
        rewardEscrowV1.vest(_entryIDs);
        return (_entryIDs, _entryIDs.length);
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

        assertEq(escrowMigrator.initializationTime(account), 0);
        assertEq(escrowMigrator.escrowVestedAtStart(account), 0);
        assertEq(escrowMigrator.numberOfMigratedEntries(account), 0);
        assertEq(escrowMigrator.totalEscrowRegistered(account), 0);
        assertEq(escrowMigrator.totalEscrowMigrated(account), 0);
        assertEq(escrowMigrator.numberOfRegisteredEntries(account), 0);
        assertEq(escrowMigrator.paidSoFar(account), 0);

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            (uint256 escrowAmount, bool migrated) =
                escrowMigrator.getRegisteredVestingEntry(account, entryID);
            assertEq(escrowAmount, 0);
            assertEq(migrated, false);
        }
    }

    function checkStateAfterStepOne(
        address account,
        uint256 index,
        uint256 amount,
        bool didInitiate
    ) internal {
        uint256[] memory _entryIDs = getEntryIDs(account, index, amount);
        checkStateAfterStepOne(account, _entryIDs, didInitiate);
    }

    function checkStateAfterStepOne(address account, uint256[] memory _entryIDs, bool didInitiate)
        internal
    {
        assertEq(escrowMigrator.initializationTime(account) > 0, didInitiate);

        assertEq(
            escrowMigrator.escrowVestedAtStart(account),
            rewardEscrowV1.totalVestedAccountBalance(account)
        );
        assertEq(escrowMigrator.numberOfRegisteredEntries(account), _entryIDs.length);
        assertEq(escrowMigrator.numberOfMigratedEntries(account), 0);
        assertEq(escrowMigrator.paidSoFar(account), 0);

        uint256 totalRegistered;

        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            assertEq(escrowMigrator.registeredEntryIDs(account, i), entryID);
            (uint256 escrowAmount, bool migrated) =
                escrowMigrator.getRegisteredVestingEntry(account, entryID);
            (, uint256 escrowAmountOriginal,) = rewardEscrowV1.getVestingEntry(account, entryID);
            assertEq(escrowAmount, escrowAmountOriginal);
            assertEq(migrated, false);
            totalRegistered += escrowAmountOriginal;
        }

        assertEq(escrowMigrator.totalEscrowRegistered(account), totalRegistered);
        assertEq(escrowMigrator.totalEscrowMigrated(account), 0);
    }

    /*//////////////////////////////////////////////////////////////
                             STEP 3 HELPERS
    //////////////////////////////////////////////////////////////*/

    function claimAndRegisterAllEntries(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries)
    {
        // check initial state
        (_entryIDs, numVestingEntries) = claimAndCheckInitialState(account);

        // step 1
        vm.prank(account);
        escrowMigrator.registerEntries(_entryIDs);
    }

    function claimRegisterAndVestAllEntries(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 toPay)
    {
        (_entryIDs,) = claimAndRegisterAllEntries(account);

        vm.prank(account);
        rewardEscrowV1.vest(_entryIDs);

        toPay = escrowMigrator.toPay(account);
    }

    /*//////////////////////////////////////////////////////////////
                             STEP 3 HELPERS
    //////////////////////////////////////////////////////////////*/

    function claimAndFullyMigrate(address account)
        internal
        returns (uint256[] memory, uint256, uint256)
    {
        (uint256[] memory _entryIDs,, uint256 toPay) = claimRegisterVestAndApprove(account);
        migrateEntries(account);
        return (_entryIDs, _entryIDs.length, toPay);
    }

    function fullyMigrate(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries, uint256 toPay)
    {
        _entryIDs = getEntryIDs(account);
        return fullyMigrate(account, _entryIDs);
    }

    function fullyMigrate(address account, uint256 index, uint256 amount)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries, uint256 toPay)
    {
        _entryIDs = getEntryIDs(account, index, amount);
        return fullyMigrate(account, _entryIDs);
    }

    function fullyMigrate(address account, uint256[] memory _entryIDs)
        internal
        returns (uint256[] memory, uint256 numVestingEntries, uint256 toPay)
    {
        (, numVestingEntries, toPay) = registerVestAndApprove(account, _entryIDs);
        migrateEntries(account, _entryIDs);
        return (_entryIDs, numVestingEntries, toPay);
    }

    function claimRegisterVestAndApprove(address account, uint256 index, uint256 amount)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries, uint256 toPay)
    {
        (_entryIDs, numVestingEntries) = claimRegisterAndVestEntries(account, index, amount);
        toPay = approve(account);

        return (_entryIDs, numVestingEntries, toPay);
    }

    function claimRegisterVestAndApprove(address account, uint256[] memory _entryIDs)
        internal
        returns (uint256[] memory, uint256 numVestingEntries, uint256 toPay)
    {
        (_entryIDs, numVestingEntries) = claimRegisterAndVestEntries(account, _entryIDs);
        toPay = approve(account);

        return (_entryIDs, numVestingEntries, toPay);
    }

    function claimRegisterVestAndApprove(address account)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries, uint256 toPay)
    {
        // register and vest
        (_entryIDs, numVestingEntries) = claimRegisterAndVestAllEntries(account);
        toPay = approve(account);
    }

    function checkStateAfterStepThree(address account) internal {
        uint256[] memory _entryIDs = getEntryIDs(account);
        checkStateAfterStepThree(account, account, _entryIDs);
    }

    function checkStateAfterStepThree(address account, uint256 index, uint256 amount) internal {
        uint256[] memory _entryIDs = getEntryIDs(account, index, amount);
        checkStateAfterStepThree(account, account, _entryIDs);
    }

    function checkStateAfterStepThree(address account, address to, uint256 index, uint256 amount)
        internal
    {
        uint256[] memory _entryIDs = getEntryIDs(account, index, amount);
        checkStateAfterStepThree(account, to, _entryIDs);
    }

    function checkStateAfterStepThree(address account, uint256[] memory _entryIDs) internal {
        checkStateAfterStepThree(account, account, _entryIDs);
    }

    function checkStateAfterStepThree(address account, address to, uint256[] memory _entryIDs)
        internal
    {
        uint256 numOfV2Entries = rewardEscrowV2.balanceOf(to);
        uint256[] memory migratedEntries =
            rewardEscrowV2.getAccountVestingEntryIDs(to, 0, numOfV2Entries);
        assertEq(numOfV2Entries, _entryIDs.length);

        uint256 totalEscrowMigrated;
        for (uint256 i = 0; i < _entryIDs.length; i++) {
            uint256 entryID = _entryIDs[i];
            uint256 migratedEntryID = migratedEntries[i];
            checkMigratedEntryAfterStepThree(account, migratedEntryID, entryID);
            (uint256 escrowAmount,,,) = checkEntryAfterStepThree(account, i, entryID);
            totalEscrowMigrated += escrowAmount;
        }

        checkStateAfterStepThreeAssertions(account, to, _entryIDs, totalEscrowMigrated);
    }

    function checkMigratedEntryAfterStepThree(
        address account,
        uint256 newEntryID,
        uint256 oldEntryID
    ) internal {
        (uint256 endTime, uint256 escrowAmount, uint256 duration, uint256 earlyVestingFee) =
            rewardEscrowV2.getVestingEntry(newEntryID);

        (uint64 registeredEndTime,, uint256 registeredDuration) =
            rewardEscrowV1.getVestingEntry(account, oldEntryID);

        (uint256 registeredEscrowAmount,) =
            escrowMigrator.getRegisteredVestingEntry(account, oldEntryID);

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
        returns (uint256 escrowAmount, uint256 duration, uint64 endTime, bool migrated)
    {
        assertEq(escrowMigrator.registeredEntryIDs(account, i), entryID);

        (escrowAmount, migrated) = escrowMigrator.getRegisteredVestingEntry(account, entryID);
        (uint64 endTimeOriginal, uint256 escrowAmountOriginal, uint256 durationOriginal) =
            rewardEscrowV1.getVestingEntry(account, entryID);
        duration = durationOriginal;
        endTime = endTimeOriginal;

        assertGt(escrowAmount, 0);
        assertEq(escrowAmountOriginal, 0);
        assertEq(migrated, true);
    }

    function checkStateAfterStepThreeAssertions(
        address account,
        address to,
        uint256[] memory _entryIDs,
        uint256 totalEscrowMigrated
    ) internal {
        assertGt(escrowMigrator.initializationTime(account), 0);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(to), totalEscrowMigrated);
        assertEq(escrowMigrator.totalEscrowMigrated(account), totalEscrowMigrated);
        assertLe(_entryIDs.length, escrowMigrator.numberOfRegisteredEntries(account));
        if (_entryIDs.length == escrowMigrator.numberOfRegisteredEntries(account)) {
            assertEq(escrowMigrator.totalEscrowRegistered(account), totalEscrowMigrated);
        }
        if (totalEscrowMigrated > 0) {
            assertLt(
                escrowMigrator.escrowVestedAtStart(account),
                rewardEscrowV1.totalVestedAccountBalance(account)
            );
        }
        assertGe(escrowMigrator.numberOfRegisteredEntries(account), _entryIDs.length);
        assertEq(escrowMigrator.numberOfMigratedEntries(account), _entryIDs.length);
        assertLe(
            escrowMigrator.paidSoFar(account),
            rewardEscrowV1.totalVestedAccountBalance(account)
                - escrowMigrator.escrowVestedAtStart(account)
        );
    }

    /*//////////////////////////////////////////////////////////////
                           INTEGRATOR HELPERS
    //////////////////////////////////////////////////////////////*/

    function registerIntegratorEntries(
        IStakingRewardsIntegrator _integrator,
        uint256[] memory _entryIDs
    ) internal {
        address beneficiary = _integrator.beneficiary();

        vm.prank(beneficiary);
        escrowMigrator.registerIntegratorEntries(address(_integrator), _entryIDs);
    }

    function registerIntegratorEntries(
        IStakingRewardsIntegrator _integrator,
        uint256 index,
        uint256 amount
    ) internal returns (uint256[] memory _entryIDs) {
        address beneficiary = _integrator.beneficiary();

        _entryIDs = getEntryIDs(address(_integrator), index, amount);

        vm.prank(beneficiary);
        escrowMigrator.registerIntegratorEntries(address(_integrator), _entryIDs);
    }

    function migrateIntegratorEntries(
        IStakingRewardsIntegrator _integrator,
        uint256[] memory _entryIDs,
        address to
    ) internal {
        address beneficiary = _integrator.beneficiary();

        vm.prank(beneficiary);
        escrowMigrator.migrateIntegratorEntries(address(_integrator), to, _entryIDs);
    }

    function claimRegisterVestAndApproveIntegrator(IStakingRewardsIntegrator _integrator)
        internal
        returns (uint256[] memory _entryIDs, uint256 numVestingEntries, uint256 toPay)
    {
        address beneficiary = _integrator.beneficiary();
        (_entryIDs, numVestingEntries) = claimAndCheckInitialState(address(_integrator));

        registerIntegratorEntries(_integrator, _entryIDs);
        vest(address(_integrator), _entryIDs);
        toPay = escrowMigrator.toPay(address(_integrator));

        vm.prank(address(_integrator));
        kwenta.transfer(beneficiary, toPay);

        approve(beneficiary);
    }
}
