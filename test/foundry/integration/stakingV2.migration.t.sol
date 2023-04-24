// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {StakingRewardsTestHelpers} from "../utils/StakingRewardsTestHelpers.t.sol";
import "../utils/Constants.t.sol";

contract StakingV2MigrationTests is StakingRewardsTestHelpers {
    /*//////////////////////////////////////////////////////////////
                            Migration Tests
    //////////////////////////////////////////////////////////////*/

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

        // switch over to StakingV2
        pauseAndSwitchToStakingRewardsV2();

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
    }
}
