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
                        Checkpointing Tests
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

    function testBalancesCheckpointsAreUpdatedFuzz(
        uint32 amount,
        uint32 blockAdvance,
        uint8 numberOfRounds
    ) public {
        vm.assume(amount > 0);

        for (uint8 i = 0; i < numberOfRounds; i++) {
            _testBalancesCheckpointsAreUpdatedFuzz(amount, blockAdvance);
        }
    }

    function _testBalancesCheckpointsAreUpdatedFuzz(
        uint256 amount,
        uint256 blockAdvance
    ) public {
        uint256 length = stakingRewardsV2.balancesLength(address(this));
        uint256 previousTotal = stakingRewardsV2.balanceOf(address(this));

        // stake
        fundAndApproveAccount(address(this), amount);
        stakingRewardsV2.stake(amount);

        // get last checkpoint
        (uint256 blockNum, uint256 value) = stakingRewardsV2.balances(
            address(this),
            length
        );

        // check values
        assertEq(blockNum, block.number);
        assertEq(value, previousTotal + amount);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());

        // update block number
        vm.roll(block.number + blockAdvance);

        // // unstake
        stakingRewardsV2.unstake(amount);

        // get last checkpoint
        (blockNum, value) = stakingRewardsV2.balances(
            address(this),
            length + 1
        );

        // check values
        assertEq(blockNum, block.number);
        assertEq(value, previousTotal);
    }
}
