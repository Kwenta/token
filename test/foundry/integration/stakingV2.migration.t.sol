// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
// import {TestHelpers} from "../utils/TestHelpers.t.sol";
import {StakingRewardsTestHelpers} from "../utils/StakingRewardsTestHelpers.t.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {MultipleMerkleDistributor} from "../../../contracts/MultipleMerkleDistributor.sol";
import {IERC20} from "../../../contracts/interfaces/IERC20.sol";
import "../utils/Constants.t.sol";

contract StakingV2MigrationTests is StakingRewardsTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    MultipleMerkleDistributor public tradingRewards;

    function setUp() public override {
        // Setup StakingV1
        treasury = createUser();
        user1 = createUser();
        user2 = createUser();
        user3 = createUser();
        user4 = createUser();
        user5 = createUser();
        mockToken = new Kwenta(
            "Mock",
            "MOCK",
            INITIAL_SUPPLY,
            address(this),
            treasury
        );
        kwenta = new Kwenta(
            "Kwenta",
            "KWENTA",
            INITIAL_SUPPLY,
            address(this),
            treasury
        );
        rewardEscrowV1 = new RewardEscrow(address(this), address(kwenta));
        supplySchedule = new SupplySchedule(address(this), treasury);
        supplySchedule.setKwenta(kwenta);
        kwenta.setSupplySchedule(address(supplySchedule));
        stakingRewardsV1 = new StakingRewards(
            address(kwenta),
            address(rewardEscrowV1),
            address(supplySchedule)
        );
        tradingRewards = new MultipleMerkleDistributor(address(this), address(kwenta));
        supplySchedule.setStakingRewards(address(stakingRewardsV1));
        supplySchedule.setTradingRewards(address(tradingRewards));
        rewardEscrowV1.setStakingRewards(address(stakingRewardsV1));

        // Stake tokens in StakingV1
        stakeFundsV1(user1, 10 ether);
        stakeFundsV1(user2, 20 ether);
        stakeFundsV1(user3, 30 ether);
        stakeFundsV1(user4, 40 ether);
        stakeFundsV1(user5, 50 ether);

        vm.warp(block.timestamp + 2 weeks);
        supplySchedule.mint();
        vm.warp(block.timestamp + 2 weeks);
        supplySchedule.mint();
        vm.warp(block.timestamp + 2 weeks);
        supplySchedule.mint();
        vm.warp(block.timestamp + 2 weeks);
        supplySchedule.mint();
        vm.warp(block.timestamp + 2 weeks);
        supplySchedule.mint();
        vm.warp(block.timestamp + 2 weeks);
        supplySchedule.mint();

        getStakingRewardsV1(user1);
        getStakingRewardsV1(user2);
        getStakingRewardsV1(user3);
        getStakingRewardsV1(user4);
        getStakingRewardsV1(user5);

        stakeAllUnstakedEscrowV1(user1);
        stakeAllUnstakedEscrowV1(user2);
        stakeAllUnstakedEscrowV1(user3);
        stakeAllUnstakedEscrowV1(user4);
        stakeAllUnstakedEscrowV1(user5);

    }

    function migrateToV2() public {
        // Deploy StakingV2
        rewardEscrowV2 = new RewardEscrowV2(address(this), address(kwenta));
        stakingRewardsV2 = new StakingRewardsV2(
            address(kwenta),
            address(rewardEscrowV2),
            address(supplySchedule)
        );

        // Pause StakingV1
        stakingRewardsV1.pauseStakingRewards();

        // Update SupplySchedule to point to StakingV2
        supplySchedule.setStakingRewards(address(stakingRewardsV2));
        rewardEscrowV2.setStakingRewards(address(stakingRewardsV2));

        // Unpause StakingV1
        stakingRewardsV1.unpauseStakingRewards();
    }
}
