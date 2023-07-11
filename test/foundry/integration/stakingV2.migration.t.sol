// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "../utils/helpers/StakingTestHelpers.t.sol";
import "../utils/Constants.t.sol";

contract StakingV2MigrationTests is StakingTestHelpers {
    /*//////////////////////////////////////////////////////////////
                            Migration Tests
    //////////////////////////////////////////////////////////////*/

    function test_Migrate_Then_Move_Funds_From_V1_To_V2_And_Generate_New_Rewards() public {
        // Stake tokens in StakingV1
        fundAccountAndStakeV1(user1, 10 ether);
        fundAccountAndStakeV1(user2, 20 ether);
        fundAccountAndStakeV1(user3, 30 ether);

        // mint new tokens
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);

        // get rewards
        getStakingRewardsV1(user1);
        getStakingRewardsV1(user2);
        getStakingRewardsV1(user3);

        // stake the rewards
        stakeAllUnstakedEscrowV1(user1);
        stakeAllUnstakedEscrowV1(user2);
        stakeAllUnstakedEscrowV1(user3);

        // switch over to StakingV2
        switchToStakingV2();

        uint256 user1EscrowV1 = rewardEscrowV1.balanceOf(user1);
        uint256 user2EscrowV1 = rewardEscrowV1.balanceOf(user2);
        uint256 user3EscrowV1 = rewardEscrowV1.balanceOf(user3);

        uint256 user1EscrowStakedV1 = stakingRewardsV1.escrowedBalanceOf(user1);
        uint256 user2EscrowStakedV1 = stakingRewardsV1.escrowedBalanceOf(user2);
        uint256 user3EscrowStakedV1 = stakingRewardsV1.escrowedBalanceOf(user3);

        uint256 user1NonEscrowedStakeV1 = stakingRewardsV1.nonEscrowedBalanceOf(user1);
        uint256 user2NonEscrowedStakeV1 = stakingRewardsV1.nonEscrowedBalanceOf(user2);
        uint256 user3NonEscrowedStakeV1 = stakingRewardsV1.nonEscrowedBalanceOf(user3);

        // assert v1 rewards have been earned
        assertGt(user1EscrowV1, 0);
        assertGt(user2EscrowV1, 0);
        assertGt(user3EscrowV1, 0);

        // v1 staked balance is equal to escrowed + non-escrowed balance
        assertEq(stakingRewardsV1.balanceOf(user1), user1EscrowStakedV1 + user1NonEscrowedStakeV1);
        assertEq(stakingRewardsV1.balanceOf(user2), user2EscrowStakedV1 + user2NonEscrowedStakeV1);
        assertEq(stakingRewardsV1.balanceOf(user3), user3EscrowStakedV1 + user3NonEscrowedStakeV1);

        // v1 reward escrow balance is equal to escrow staked balance
        assertEq(user1EscrowV1, user1EscrowStakedV1);
        assertEq(user2EscrowV1, user2EscrowStakedV1);
        assertEq(user3EscrowV1, user3EscrowStakedV1);

        // Migrate non-escrow stake from StakingRewardsV1 to StakingRewardsV2
        exitStakingV1(user1);
        stakeFundsV2(user1, user1NonEscrowedStakeV1);
        exitStakingV1(user2);
        stakeFundsV2(user2, user2NonEscrowedStakeV1);
        exitStakingV1(user3);
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

        // mint new tokens
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);

        // get rewards
        getStakingRewardsV2(user1);
        getStakingRewardsV2(user2);
        getStakingRewardsV2(user3);

        // stake the rewards
        stakeAllUnstakedEscrowV2(user1);
        stakeAllUnstakedEscrowV2(user2);
        stakeAllUnstakedEscrowV2(user3);

        // check StakingRewardsV1 balance unchanged
        assertEq(stakingRewardsV1.nonEscrowedBalanceOf(user1), 0);
        assertEq(stakingRewardsV1.nonEscrowedBalanceOf(user2), 0);
        assertEq(stakingRewardsV1.nonEscrowedBalanceOf(user3), 0);
        assertEq(stakingRewardsV1.escrowedBalanceOf(user1), user1EscrowStakedV1);
        assertEq(stakingRewardsV1.escrowedBalanceOf(user2), user2EscrowStakedV1);
        assertEq(stakingRewardsV1.escrowedBalanceOf(user3), user3EscrowStakedV1);
        assertEq(stakingRewardsV1.balanceOf(user1), user1EscrowStakedV1);
        assertEq(stakingRewardsV1.balanceOf(user2), user2EscrowStakedV1);
        assertEq(stakingRewardsV1.balanceOf(user3), user3EscrowStakedV1);

        // check RewardEscrowV1 balance unchanged
        assertEq(rewardEscrowV1.balanceOf(user1), user1EscrowV1);
        assertEq(rewardEscrowV1.balanceOf(user2), user2EscrowV1);
        assertEq(rewardEscrowV1.balanceOf(user3), user3EscrowV1);
        assertEq(rewardEscrowV1.balanceOf(user1), user1EscrowStakedV1);
        assertEq(rewardEscrowV1.balanceOf(user2), user2EscrowStakedV1);
        assertEq(rewardEscrowV1.balanceOf(user3), user3EscrowStakedV1);

        uint256 user1EscrowStakedV2 = stakingRewardsV2.escrowedBalanceOf(user1);
        uint256 user2EscrowStakedV2 = stakingRewardsV2.escrowedBalanceOf(user2);
        uint256 user3EscrowStakedV2 = stakingRewardsV2.escrowedBalanceOf(user3);

        user1NonEscrowedStakeV2 = stakingRewardsV2.nonEscrowedBalanceOf(user1);
        user2NonEscrowedStakeV2 = stakingRewardsV2.nonEscrowedBalanceOf(user2);
        user3NonEscrowedStakeV2 = stakingRewardsV2.nonEscrowedBalanceOf(user3);

        // assert v2 rewards have been earned
        assertGt(rewardEscrowV2.escrowedBalanceOf(user1), 0);
        assertGt(rewardEscrowV2.escrowedBalanceOf(user2), 0);
        assertGt(rewardEscrowV2.escrowedBalanceOf(user3), 0);

        // v2 staked balance is equal to escrowed + non-escrowed balance
        assertEq(stakingRewardsV2.balanceOf(user1), user1EscrowStakedV2 + user1NonEscrowedStakeV2);
        assertEq(stakingRewardsV2.balanceOf(user2), user2EscrowStakedV2 + user2NonEscrowedStakeV2);
        assertEq(stakingRewardsV2.balanceOf(user3), user3EscrowStakedV2 + user3NonEscrowedStakeV2);

        // v2 reward escrow balance is equal to escrow staked balance
        assertEq(rewardEscrowV2.escrowedBalanceOf(user1), user1EscrowStakedV2);
        assertEq(rewardEscrowV2.escrowedBalanceOf(user2), user2EscrowStakedV2);
        assertEq(rewardEscrowV2.escrowedBalanceOf(user3), user3EscrowStakedV2);
    }

    function test_Migrate_Then_Move_Funds_From_V1_To_V2_And_Generate_New_Rewards_Fuzz(
        uint32 maxFundingAmount,
        uint8 numberOfStakers
    ) public {
        vm.assume(maxFundingAmount > 0);
        vm.assume(numberOfStakers < 50);

        // create stakers
        address[] memory stakers = new address[](numberOfStakers);
        for (uint8 i = 0; i < numberOfStakers; i++) {
            address staker = createUser();
            stakers[i] = staker;
        }

        // Stake tokens in StakingV1
        for (uint8 i = 0; i < numberOfStakers; i++) {
            uint256 fundingAmount = getPseudoRandomNumber(maxFundingAmount, 1, i);
            fundAccountAndStakeV1(stakers[i], fundingAmount);
        }

        // mint new tokens
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);

        // get rewards
        for (uint8 i = 0; i < numberOfStakers; i++) {
            getStakingRewardsV1(stakers[i]);
        }

        // stake the rewards
        for (uint8 i = 0; i < numberOfStakers; i++) {
            stakeAllUnstakedEscrowV1(stakers[i]);
        }

        // switch over to StakingV2
        switchToStakingV2();

        uint256[] memory userNonEscrowedStakeV1 = new uint256[](numberOfStakers);
        uint256[] memory userEscrowedStakeV1 = new uint256[](numberOfStakers);
        uint256[] memory userEscrowV1 = new uint256[](numberOfStakers);
        for (uint8 i = 0; i < numberOfStakers; i++) {
            address staker = stakers[i];
            userEscrowedStakeV1[i] = stakingRewardsV1.escrowedBalanceOf(staker);
            userNonEscrowedStakeV1[i] = stakingRewardsV1.nonEscrowedBalanceOf(staker);
            userEscrowV1[i] = rewardEscrowV1.balanceOf(staker);

            // assert v1 rewards have been earned
            assertGt(userEscrowV1[i], 0);

            // v1 staked balance is equal to escrowed + non-escrowed balance
            assertEq(
                stakingRewardsV1.balanceOf(staker),
                userEscrowedStakeV1[i] + userNonEscrowedStakeV1[i]
            );

            // v1 reward escrow balance is equal to escrow staked balance
            assertEq(userEscrowV1[i], userEscrowedStakeV1[i]);
        }

        // Migrate non-escrow stake from StakingRewardsV1 to StakingRewardsV2
        for (uint8 i = 0; i < numberOfStakers; i++) {
            unstakeFundsV1(stakers[i], userNonEscrowedStakeV1[i]);
            stakeFundsV2(stakers[i], userNonEscrowedStakeV1[i]);
        }

        for (uint8 i = 0; i < numberOfStakers; i++) {
            // check full balance migrated
            assertEq(userNonEscrowedStakeV1[i], stakingRewardsV2.nonEscrowedBalanceOf(stakers[i]));

            // update non-escrowed stake
            userNonEscrowedStakeV1[i] = stakingRewardsV1.nonEscrowedBalanceOf(stakers[i]);

            // check nothing left in V1
            assertEq(userNonEscrowedStakeV1[i], 0);
        }

        // mint new tokens
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);

        for (uint8 i = 0; i < numberOfStakers; i++) {
            // get rewards
            getStakingRewardsV2(stakers[i]);

            // stake the rewards
            stakeAllUnstakedEscrowV2(stakers[i]);
        }

        // check StakingRewardsV1 balance unchanged
        for (uint8 i = 0; i < numberOfStakers; i++) {
            assertEq(stakingRewardsV1.nonEscrowedBalanceOf(stakers[i]), 0);
            assertEq(stakingRewardsV1.escrowedBalanceOf(stakers[i]), userEscrowedStakeV1[i]);
            assertEq(stakingRewardsV1.balanceOf(stakers[i]), userEscrowedStakeV1[i]);
        }

        // check RewardEscrowV1 balance unchanged
        for (uint8 i = 0; i < numberOfStakers; i++) {
            assertEq(rewardEscrowV1.balanceOf(stakers[i]), userEscrowV1[i]);
            assertEq(rewardEscrowV1.balanceOf(stakers[i]), userEscrowedStakeV1[i]);
        }

        for (uint8 i = 0; i < numberOfStakers; i++) {
            uint256 userEscrowStakedV2 = stakingRewardsV2.escrowedBalanceOf(stakers[i]);
            uint256 userNonEscrowedStakeV2 = stakingRewardsV2.nonEscrowedBalanceOf(stakers[i]);

            // assert v2 rewards have been earned
            assertGt(rewardEscrowV2.escrowedBalanceOf(stakers[i]), 0);

            // v2 staked balance is equal to escrowed + non-escrowed balance
            assertEq(
                stakingRewardsV2.balanceOf(stakers[i]), userEscrowStakedV2 + userNonEscrowedStakeV2
            );

            // v2 reward escrow balance is equal to escrow staked balance
            assertEq(rewardEscrowV2.escrowedBalanceOf(stakers[i]), userEscrowStakedV2);
        }
    }
}
