// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {StakingRewardsTestHelpers} from "../utils/StakingRewardsTestHelpers.t.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import "../utils/Constants.t.sol";

contract StakingV2CheckpointingTests is StakingRewardsTestHelpers {
    /*//////////////////////////////////////////////////////////////
                        Balance Checkpoint Tests
    //////////////////////////////////////////////////////////////*/

    function testBalancesCheckpointsAreUpdated() public {
        // stake
        fundAndApproveAccount(address(this), TEST_VALUE);
        stakingRewardsV2.stake(TEST_VALUE);

        // get last checkpoint
        (uint256 blockNum, uint256 value) = stakingRewardsV2.balances(
            address(this),
            0
        );

        // check values
        assertEq(blockNum, block.number);
        assertEq(value, TEST_VALUE);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());

        // update block number
        vm.roll(block.number + 1);

        // unstake
        stakingRewardsV2.unstake(TEST_VALUE);

        // get last checkpoint
        (blockNum, value) = stakingRewardsV2.balances(address(this), 1);

        // check values
        assertEq(blockNum, block.number);
        assertEq(value, 0);
    }

    function testBalancesCheckpointsAreUpdatedEscrowStaking() public {
        // stake
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.stakeEscrow(address(this), TEST_VALUE);

        // get last checkpoint
        (uint256 blockNum, uint256 value) = stakingRewardsV2.balances(
            address(this),
            0
        );

        // check values
        assertEq(blockNum, block.number);
        assertEq(value, TEST_VALUE);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());

        // update block number
        vm.roll(block.number + 1);

        // unstake
        vm.prank(address(rewardEscrow));
        stakingRewardsV2.unstakeEscrow(address(this), TEST_VALUE);

        // get last checkpoint
        (blockNum, value) = stakingRewardsV2.balances(address(this), 1);

        // check values
        assertEq(blockNum, block.number);
        assertEq(value, 0);
    }

    function testBalancesCheckpointsAreUpdatedFuzz(
        uint32 maxAmountStaked,
        uint8 numberOfRounds
    ) public {
        vm.assume(maxAmountStaked > 0);
        // keep the number of rounds low to keep tests fast
        vm.assume(numberOfRounds < 50);

        // Stake and unstake in each iteration/round and check that the checkpoints are updated correctly
        for (uint8 i = 0; i < numberOfRounds; i++) {
            // get random values for each round
            uint256 amountToStake = getPseudoRandomNumber(
                maxAmountStaked,
                1,
                i
            );
            uint256 amountToUnstake = getPseudoRandomNumber(
                amountToStake,
                1,
                i
            );
            uint256 blockAdvance = getPseudoRandomNumber(amountToUnstake, 0, i);

            // get initial values
            uint256 length = stakingRewardsV2.balancesLength(address(this));
            uint256 previousTotal = stakingRewardsV2.balanceOf(address(this));

            // stake
            fundAndApproveAccount(address(this), amountToStake);
            stakingRewardsV2.stake(amountToStake);

            // get last checkpoint
            (uint256 blockNum, uint256 value) = stakingRewardsV2.balances(
                address(this),
                length
            );

            // check checkpoint values
            assertEq(blockNum, block.number);
            assertEq(value, previousTotal + amountToStake);

            // move beyond cold period
            vm.warp(
                block.timestamp + stakingRewardsV2.unstakingCooldownPeriod()
            );

            // update block number
            vm.roll(block.number + blockAdvance);

            // // unstake
            stakingRewardsV2.unstake(amountToUnstake);

            // get last checkpoint
            (blockNum, value) = stakingRewardsV2.balances(
                address(this),
                length + 1
            );

            // check checkpoint values
            assertEq(blockNum, block.number);
            assertEq(value, previousTotal + amountToStake - amountToUnstake);
        }
    }

    function testBalancesCheckpointsAreUpdatedEscrowStakedFuzz(
        uint32 maxAmountStaked,
        uint8 numberOfRounds
    ) public {
        vm.assume(maxAmountStaked > 0);
        // keep the number of rounds low to keep tests fast
        vm.assume(numberOfRounds < 50);

        // Stake and unstake in each iteration/round and check that the checkpoints are updated correctly
        for (uint8 i = 0; i < numberOfRounds; i++) {
            // get random values for each round
            uint256 amountToStake = getPseudoRandomNumber(
                maxAmountStaked,
                1,
                i
            );
            uint256 amountToUnstake = getPseudoRandomNumber(
                amountToStake,
                1,
                i
            );
            uint256 blockAdvance = getPseudoRandomNumber(amountToUnstake, 0, i);

            // get initial values
            uint256 length = stakingRewardsV2.balancesLength(address(this));
            uint256 previousTotal = stakingRewardsV2.balanceOf(address(this));

            // stake
            vm.prank(address(rewardEscrow));
            stakingRewardsV2.stakeEscrow(address(this), amountToStake);

            // get last checkpoint
            (uint256 blockNum, uint256 value) = stakingRewardsV2.balances(
                address(this),
                length
            );

            // check checkpoint values
            assertEq(blockNum, block.number);
            assertEq(value, previousTotal + amountToStake);

            // move beyond cold period
            vm.warp(
                block.timestamp + stakingRewardsV2.unstakingCooldownPeriod()
            );

            // update block number
            vm.roll(block.number + blockAdvance);

            // // unstake
            vm.prank(address(rewardEscrow));
            stakingRewardsV2.unstakeEscrow(address(this), amountToUnstake);

            // get last checkpoint
            (blockNum, value) = stakingRewardsV2.balances(
                address(this),
                length + 1
            );

            // check checkpoint values
            assertEq(blockNum, block.number);
            assertEq(value, previousTotal + amountToStake - amountToUnstake);
        }
    }
}
