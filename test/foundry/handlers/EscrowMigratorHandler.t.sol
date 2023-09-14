// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {EscrowMigrator} from "../../../contracts/EscrowMigrator.sol";
import {EscrowMigratorTestHelpers} from "../utils/helpers/EscrowMigratorTestHelpers.t.sol";

import "forge-std/Test.sol";

contract EscrowMigratorHandler is EscrowMigratorTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    address[] migrators;
    address currentMigrator;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(
        address _treasury,
        address _owner,
        Kwenta _kwenta,
        RewardEscrow _rewardEscrowV1,
        SupplySchedule _supplySchedule,
        StakingRewards _stakingRewardsV1,
        RewardEscrowV2 _rewardEscrowV2,
        StakingRewardsV2 _stakingRewardsV2,
        EscrowMigrator _escrowMigrator,
        address[] memory _migrators
    ) {
        treasury = _treasury;
        owner = _owner;
        kwenta = _kwenta;
        rewardEscrowV1 = _rewardEscrowV1;
        supplySchedule = _supplySchedule;
        stakingRewardsV1 = _stakingRewardsV1;
        rewardEscrowV2 = _rewardEscrowV2;
        stakingRewardsV2 = _stakingRewardsV2;
        escrowMigrator = _escrowMigrator;
        migrators = _migrators;

        vm.prank(treasury);
        kwenta.transfer(address(escrowMigrator), 1000 ether);
    }

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    modifier useMigrator(uint256 migratorSeedIndex) {
        currentMigrator = migrators[bound(migratorSeedIndex, 0, migrators.length - 1)];
        _;
    }

    /*//////////////////////////////////////////////////////////////
                          BLOCK SETUP FUNCTION
    //////////////////////////////////////////////////////////////*/

    function setUp() public pure override {
        return;
    }

    /*//////////////////////////////////////////////////////////////
                                GENERIC
    //////////////////////////////////////////////////////////////*/

    function advanceTime(uint16 secs) public {
        vm.warp(block.timestamp + secs);
    }

    /*//////////////////////////////////////////////////////////////
                            REWARD ESCROW V1
    //////////////////////////////////////////////////////////////*/

    function createABunchOfEntries(
        uint256 _seed,
        uint64 _amount,
        uint24 _duration,
        uint8 _numEntries
    ) public useMigrator(_seed) {
        for (uint256 i = 0; i < _numEntries; i++) {
            createRewardEscrowEntryV1(currentMigrator, _amount, _duration);
        }
    }

    function createABunchOfEntries(
        address _account,
        uint64 _amount,
        uint24 _duration,
        uint8 _numEntries
    ) internal {
        for (uint256 i = 0; i < _numEntries; i++) {
            createRewardEscrowEntryV1(_account, _amount, _duration);
        }
    }

    function createV1Entry(uint256 _seed, uint64 _amount, uint24 _duration)
        public
        useMigrator(_seed)
    {
        createRewardEscrowEntryV1(currentMigrator, _amount, _duration);
    }

    function stakeV1Escrow(uint256 _seed) public useMigrator(_seed) {
        stakeAllUnstakedEscrowV1(currentMigrator);
    }

    function unstakeV1Escrow(uint256 _seed) public useMigrator(_seed) {
        unstakeAllUnstakedEscrowV1(currentMigrator);
    }

    function validVestV1(uint256 _seed) public useMigrator(_seed) {
        vest(currentMigrator);
    }

    function validVestV1(uint256 _seed, uint16 index, uint16 amount) public useMigrator(_seed) {
        vest(currentMigrator, index, amount);
    }

    /*//////////////////////////////////////////////////////////////
                         ESCROW MIGRATOR BASICS
    //////////////////////////////////////////////////////////////*/

    function validRegisterEntries(uint256 _seed) public useMigrator(_seed) {
        registerEntries(currentMigrator);
    }

    function validRegisterEntries(uint256 _seed, uint16 index, uint16 amount)
        public
        useMigrator(_seed)
    {
        registerEntries(currentMigrator, index, amount);
    }

    function validMigrateEntries(uint256 _seed) public useMigrator(_seed) {
        migrateEntries(currentMigrator);
    }

    function validMigrateEntries(uint256 _seed, uint16 index, uint16 amount)
        public
        useMigrator(_seed)
    {
        migrateEntries(currentMigrator, index, amount);
    }

    function maxApproveMigrator(uint256 _seed) public useMigrator(_seed) {
        approve(currentMigrator);
    }

    /*//////////////////////////////////////////////////////////////
                        ESCROW MIGRATOR ADVANCED
    //////////////////////////////////////////////////////////////*/

    function createClaimRegister(uint256 _seed, uint64 _amount, uint24 _duration, uint8 _numEntries)
        public
        useMigrator(_seed)
    {
        createABunchOfEntries(currentMigrator, _amount, _duration, _numEntries);
        claimAndRegisterEntries(currentMigrator, 0, _numEntries);
    }

    function createClaimRegisterVest(
        uint256 _seed,
        uint64 _amount,
        uint24 _duration,
        uint8 _numEntries
    ) public useMigrator(_seed) {
        createABunchOfEntries(currentMigrator, _amount, _duration, _numEntries);
        claimRegisterAndVestEntries(currentMigrator, 0, _numEntries);
    }

    function createClaimRegisterVestApprove(
        uint256 _seed,
        uint64 _amount,
        uint24 _duration,
        uint8 _numEntries
    ) public useMigrator(_seed) {
        createABunchOfEntries(currentMigrator, _amount, _duration, _numEntries);
        claimRegisterVestAndApprove(currentMigrator, 0, _numEntries);
    }

    function createClaimRegisterVestApproveMigrate(
        uint256 _seed,
        uint64 _amount,
        uint24 _duration,
        uint8 _numEntries
    ) public useMigrator(_seed) {
        createABunchOfEntries(currentMigrator, _amount, _duration, _numEntries);
        claimAndFullyMigrate(currentMigrator);
    }

    function approveMigrate(uint256 _seed) public useMigrator(_seed) {
        approveAndMigrate(currentMigrator);
    }

    function vestApproveMigrate(uint256 _seed) public useMigrator(_seed) {
        vestAndApprove(currentMigrator);
        fullyMigrate(currentMigrator);
    }

    function vestApprove(uint256 _seed) public useMigrator(_seed) {
        vestAndApprove(currentMigrator);
    }

    function registerVest(uint256 _seed) public useMigrator(_seed) {
        registerAndVestEntries(currentMigrator);
    }

    function registerVestApprove(uint256 _seed) public useMigrator(_seed) {
        registerVestAndApprove(currentMigrator);
    }

    function migrateAll(uint256 _seed) public useMigrator(_seed) {
        fullyMigrate(currentMigrator);
    }

    function updateTotalLocked(uint256 _seed) public useMigrator(_seed) {
        escrowMigrator.updateTotalLocked(currentMigrator);
    }

    function recoverExcessFunds() public {
        vm.prank(owner);
        escrowMigrator.recoverExcessFunds();
    }

    /*//////////////////////////////////////////////////////////////
                           STAKING REWARDS V1
    //////////////////////////////////////////////////////////////*/

    function fundAndStakeV1(uint256 _seed, uint64 _amount) public useMigrator(_seed) {
        fundAccountAndStakeV1(currentMigrator, _amount);
    }

    function unstakeV1(uint256 _seed, uint64 _amount) public useMigrator(_seed) {
        unstakeFundsV1(currentMigrator, _amount);
    }

    function exitV1(uint256 _seed) public useMigrator(_seed) {
        exitStakingV1(currentMigrator);
    }

    function getV1Rewards(uint256 _seed) public useMigrator(_seed) {
        getStakingRewardsV1(currentMigrator);
    }

    function addV1Rewards(uint64 _reward) public {
        addNewRewardsToStakingRewardsV1(_reward);
        vm.warp(block.timestamp + 1 weeks);
    }
}
