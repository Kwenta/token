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
    }

    function testManualStakingAndUnstaking() public {
        // Stake tokens in StakingV1
        fundAccountAndStakeV1(user1, 10 ether);
        fundAccountAndStakeV1(user2, 20 ether);
        fundAccountAndStakeV1(user3, 30 ether);
        fundAccountAndStakeV1(user4, 40 ether);
        fundAccountAndStakeV1(user5, 50 ether);

        // mint new tokens
        warpAndMintV1(2 weeks);
        warpAndMintV1(2 weeks);
        warpAndMintV1(2 weeks);
        warpAndMintV1(2 weeks);
        warpAndMintV1(2 weeks);
        warpAndMintV1(2 weeks);

        // get rewards
        getStakingRewardsV1(user1);
        getStakingRewardsV1(user2);
        getStakingRewardsV1(user3);

        // stake the rewards
        stakeAllUnstakedEscrowV1(user1);
        stakeAllUnstakedEscrowV1(user2);
        stakeAllUnstakedEscrowV1(user3);

        // Deploy StakingV2
        rewardEscrowV2 = new RewardEscrowV2(address(this), address(kwenta));
        stakingRewardsV2 = new StakingRewardsV2(
            address(kwenta),
            address(rewardEscrowV2),
            address(supplySchedule),
            address(stakingRewardsV1)
        );

        // Pause StakingV1
        stakingRewardsV1.pauseStakingRewards();

        // Update SupplySchedule to point to StakingV2
        supplySchedule.setStakingRewards(address(stakingRewardsV2));
        rewardEscrowV2.setStakingRewards(address(stakingRewardsV2));

        // Unpause StakingV1
        stakingRewardsV1.unpauseStakingRewards();

        uint256 user1StakeV1 = stakingRewardsV1.balanceOf(user1);
        uint256 user2StakeV1 = stakingRewardsV1.balanceOf(user2);
        uint256 user3StakeV1 = stakingRewardsV1.balanceOf(user3);

        uint256 user1EscrowV1 = rewardEscrowV1.balanceOf(user1);
        uint256 user2EscrowV1 = rewardEscrowV1.balanceOf(user2);
        uint256 user3EscrowV1 = rewardEscrowV1.balanceOf(user3);

        uint256 user1EscrowStakedV1 = stakingRewardsV1.escrowedBalanceOf(user1);
        uint256 user2EscrowStakedV1 = stakingRewardsV1.escrowedBalanceOf(user2);
        uint256 user3EscrowStakedV1 = stakingRewardsV1.escrowedBalanceOf(user3);

        uint256 user1NonEscrowedStakeV1 = stakingRewardsV1.nonEscrowedBalanceOf(user1);
        uint256 user2NonEscrowedStakeV1 = stakingRewardsV1.nonEscrowedBalanceOf(user2);
        uint256 user3NonEscrowedStakeV1 = stakingRewardsV1.nonEscrowedBalanceOf(user3);

        assertEq(user1StakeV1, user1EscrowStakedV1 + user1NonEscrowedStakeV1);
        assertEq(user1EscrowV1, user1EscrowStakedV1);
        assertEq(user2StakeV1, user2EscrowStakedV1 + user2NonEscrowedStakeV1);
        assertEq(user2EscrowV1, user2EscrowStakedV1);
        assertEq(user3StakeV1, user3EscrowStakedV1 + user3NonEscrowedStakeV1);
        assertEq(user3EscrowV1, user3EscrowStakedV1);

        // Migrate non-escrow stake from StakingRewardsV1 to StakingRewardsV2
        unstakeFundsV1(user1, user1NonEscrowedStakeV1);
        stakeFundsV2(user1, user1NonEscrowedStakeV1);
        unstakeFundsV1(user2, user2NonEscrowedStakeV1);
        stakeFundsV2(user2, user2NonEscrowedStakeV1);
        unstakeFundsV1(user3, user3NonEscrowedStakeV1);
        stakeFundsV2(user3, user3NonEscrowedStakeV1);

        uint256 user1NonEscrowedStakeV2 = stakingRewardsV2.nonEscrowedBalanceOf(user1);
        uint256 user2NonEscrowedStakeV2 = stakingRewardsV2.nonEscrowedBalanceOf(user2);
        uint256 user3NonEscrowedStakeV2 = stakingRewardsV2.nonEscrowedBalanceOf(user3);

        // check full balance migrated
        assertEq(user1NonEscrowedStakeV1, user1NonEscrowedStakeV2);
        assertEq(user2NonEscrowedStakeV1, user2NonEscrowedStakeV2);
        assertEq(user3NonEscrowedStakeV1, user3NonEscrowedStakeV2);

        user1NonEscrowedStakeV1 = stakingRewardsV1.nonEscrowedBalanceOf(user1);
        user2NonEscrowedStakeV1 = stakingRewardsV1.nonEscrowedBalanceOf(user2);
        user3NonEscrowedStakeV1 = stakingRewardsV1.nonEscrowedBalanceOf(user3);

        // check nothing left in V1
        assertEq(user1NonEscrowedStakeV1, 0);
        assertEq(user2NonEscrowedStakeV1, 0);
        assertEq(user3NonEscrowedStakeV1, 0);

        // // Check staked escrow from StakingRewardsV1 is accounted for in StakingRewardsV2

        // uint256 user1Balance = stakingRewardsV2.balanceOf(user1);
        // user1EscrowStakedV1 = stakingRewardsV1.escrowedBalanceOf(user1);
        // uint256 rewardPerToken = stakingRewardsV2.rewardPerToken();
        // uint256 user1RewardPerTokenPaid = stakingRewardsV2.userRewardPerTokenPaid(user1);
        // uint256 user1Rewards = stakingRewardsV2.rewards(user1);

        // // uint256 expectedRewardOutput = 
    }
}
