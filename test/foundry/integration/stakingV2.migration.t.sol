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
        fundAccountAndStakeV1(user1, 10 ether);
        fundAccountAndStakeV1(user2, 20 ether);
        fundAccountAndStakeV1(user3, 30 ether);
        fundAccountAndStakeV1(user4, 40 ether);
        fundAccountAndStakeV1(user5, 50 ether);

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

    function testMigrateToV2() public {
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

        uint256 user1Stake = stakingRewardsV1.balanceOf(user1);
        uint256 user2Stake = stakingRewardsV1.balanceOf(user2);
        uint256 user3Stake = stakingRewardsV1.balanceOf(user3);
        // uint256 user4Stake = stakingRewardsV1.balanceOf(user4);
        // uint256 user5Stake = stakingRewardsV1.balanceOf(user5);

        uint256 user1Escrow = rewardEscrowV1.balanceOf(user1);
        uint256 user2Escrow = rewardEscrowV1.balanceOf(user2);
        uint256 user3Escrow = rewardEscrowV1.balanceOf(user3);
        // uint256 user4Escrow = rewardEscrowV1.balanceOf(user4);
        // uint256 user5Escrow = rewardEscrowV1.balanceOf(user5);

        uint256 user1EscrowStaked = stakingRewardsV1.escrowedBalanceOf(user1);
        uint256 user2EscrowStaked = stakingRewardsV1.escrowedBalanceOf(user2);
        uint256 user3EscrowStaked = stakingRewardsV1.escrowedBalanceOf(user3);
        // uint256 user4EscrowStaked = stakingRewardsV1.escrowedBalanceOf(user4);
        // uint256 user5EscrowStaked = stakingRewardsV1.escrowedBalanceOf(user5);

        uint256 user1NonEscrowedStake = stakingRewardsV1.nonEscrowedBalanceOf(user1);
        uint256 user2NonEscrowedStake = stakingRewardsV1.nonEscrowedBalanceOf(user2);
        uint256 user3NonEscrowedStake = stakingRewardsV1.nonEscrowedBalanceOf(user3);
        // uint256 user4NonEscrowedStake = stakingRewardsV1.nonEscrowedBalanceOf(user4);
        // uint256 user5NonEscrowedStake = stakingRewardsV1.nonEscrowedBalanceOf(user5);

        assertEq(user1Stake, user1EscrowStaked + user1NonEscrowedStake);
        assertEq(user1Escrow, user1EscrowStaked);
        assertEq(user2Stake, user2EscrowStaked + user2NonEscrowedStake);
        assertEq(user2Escrow, user2EscrowStaked);
        assertEq(user3Stake, user3EscrowStaked + user3NonEscrowedStake);
        assertEq(user3Escrow, user3EscrowStaked);

        // Migrate StakingV1 to StakingV2
        unstakeFundsV1(user1, user1NonEscrowedStake);
        stakeFundsV2(user1, user1NonEscrowedStake);
    }
}
