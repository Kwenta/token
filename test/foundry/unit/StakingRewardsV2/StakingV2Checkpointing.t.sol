// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import "../../utils/Constants.t.sol";

contract StakingV2CheckpointingTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                        Balance Checkpoint Tests
    //////////////////////////////////////////////////////////////*/

    function test_Balances_Checkpoints_Are_Updated() public {
        // stake
        fundAccountAndStakeV2(address(this), TEST_VALUE);

        // get last checkpoint
        (uint256 ts, uint256 blk, uint256 value) =
            stakingRewardsV2.balancesCheckpoints(address(this), 0);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, TEST_VALUE);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());

        // update block timestamp
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // unstake
        stakingRewardsV2.unstake(TEST_VALUE);

        // get last checkpoint
        (ts, blk, value) = stakingRewardsV2.balancesCheckpoints(address(this), 1);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, 0);
    }

    function test_Updating_Balance_Checkpoints_At_Same_Time() public {
        // stake
        fundAccountAndStakeV2(address(this), TEST_VALUE * 2);

        // get last checkpoint
        (uint256 ts, uint256 blk, uint256 value) =
            stakingRewardsV2.balancesCheckpoints(address(this), 0);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, TEST_VALUE * 2);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());

        // update block timestamp
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // unstake twice
        stakingRewardsV2.unstake(TEST_VALUE);
        stakingRewardsV2.unstake(TEST_VALUE);

        // get last checkpoint
        (ts, blk, value) = stakingRewardsV2.balancesCheckpoints(address(this), 1);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, 0);
    }

    function test_Balances_Checkpoints_Are_Updated_Escrow_Staking() public {
        // stake
        stakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (uint256 ts, uint256 blk, uint256 value) =
            stakingRewardsV2.balancesCheckpoints(address(this), 0);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, TEST_VALUE);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());

        // update block timestamp
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // unstake
        unstakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (ts, blk, value) = stakingRewardsV2.balancesCheckpoints(address(this), 1);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, 0);
    }

    function test_Balances_Checkpoints_Updated_At_Same_Time_Escrow_Staking() public {
        // stake
        stakeEscrowedFundsV2(address(this), TEST_VALUE * 2);

        // get last checkpoint
        (uint256 ts, uint256 blk, uint256 value) =
            stakingRewardsV2.balancesCheckpoints(address(this), 0);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, TEST_VALUE * 2);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());

        // update block timestamp
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // unstake
        unstakeEscrowedFundsV2(address(this), TEST_VALUE);
        unstakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (ts, blk, value) = stakingRewardsV2.balancesCheckpoints(address(this), 1);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, 0);
    }

    function test_Balances_Checkpoints_Are_Updated_Fuzz(
        uint32 maxAmountStaked,
        uint8 numberOfRounds
    ) public {
        vm.assume(maxAmountStaked > 0);
        // keep the number of rounds low to keep tests fast
        vm.assume(numberOfRounds < 50);

        // Stake and unstake in each iteration/round and check that the checkpoints are updated correctly
        for (uint8 i = 0; i < numberOfRounds; i++) {
            // get random values for each round
            uint256 amountToStake = getPseudoRandomNumber(maxAmountStaked, 1, i);
            uint256 amountToUnstake = getPseudoRandomNumber(amountToStake, 1, i);
            uint256 timestampAdvance = getPseudoRandomNumber(amountToUnstake, 0, i);

            // get initial values
            uint256 previousTotal = stakingRewardsV2.balanceOf(address(this));

            // stake
            fundAccountAndStakeV2(address(this), amountToStake);

            // get last checkpoint
            uint256 length = stakingRewardsV2.balancesCheckpointsLength(address(this));
            uint256 finalIndex = length == 0 ? 0 : length - 1;
            (uint256 ts, uint256 blk, uint256 value) =
                stakingRewardsV2.balancesCheckpoints(address(this), finalIndex);

            // check checkpoint values
            assertEq(ts, block.timestamp);
            assertEq(blk, block.number);
            assertEq(value, previousTotal + amountToStake);

            // move beyond cold period
            vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());

            // update block timestamp
            vm.warp(block.timestamp + timestampAdvance);
            vm.roll(block.number + 1);

            // unstake
            stakingRewardsV2.unstake(amountToUnstake);

            // get last checkpoint
            uint256 newIndex = finalIndex + 1;
            (ts, blk, value) = stakingRewardsV2.balancesCheckpoints(address(this), newIndex);

            // check checkpoint values
            assertEq(ts, block.timestamp);
            assertEq(blk, block.number);
            assertEq(value, previousTotal + amountToStake - amountToUnstake);

            // update block timestamp
            vm.warp(block.timestamp + timestampAdvance);
        }
    }

    function test_Balances_Checkpoints_Are_Updated_Escrow_Staked_Fuzz(
        uint32 maxAmountStaked,
        uint8 numberOfRounds
    ) public {
        vm.assume(maxAmountStaked > 0);
        // keep the number of rounds low to keep tests fast
        vm.assume(numberOfRounds < 50);

        // Stake and unstake in each iteration/round and check that the checkpoints are updated correctly
        for (uint8 i = 0; i < numberOfRounds; i++) {
            // get random values for each round
            uint256 amountToStake = getPseudoRandomNumber(maxAmountStaked, 1, i);
            uint256 amountToUnstake = getPseudoRandomNumber(amountToStake, 1, i);
            uint256 timestampAdvance = getPseudoRandomNumber(amountToUnstake, 0, i);

            // get initial values
            uint256 previousTotal = stakingRewardsV2.balanceOf(address(this));

            // stake
            stakeEscrowedFundsV2(address(this), amountToStake);

            // get last checkpoint
            uint256 length = stakingRewardsV2.balancesCheckpointsLength(address(this));
            uint256 finalIndex = length == 0 ? 0 : length - 1;
            (uint256 ts, uint256 blk, uint256 value) =
                stakingRewardsV2.balancesCheckpoints(address(this), finalIndex);

            // check checkpoint values
            assertEq(ts, block.timestamp);
            assertEq(blk, block.number);
            assertEq(value, previousTotal + amountToStake);

            // move beyond cold period
            vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());

            // update block timestamp
            vm.warp(block.timestamp + timestampAdvance);
            vm.roll(block.number + 1);

            // unstake
            unstakeEscrowedFundsV2(address(this), amountToUnstake);

            // get last checkpoint
            uint256 newIndex = finalIndex + 1;
            (ts, blk, value) = stakingRewardsV2.balancesCheckpoints(address(this), newIndex);

            // check checkpoint values
            assertEq(ts, block.timestamp);
            assertEq(blk, block.number);
            assertEq(value, previousTotal + amountToStake - amountToUnstake);

            // update block timestamp
            vm.warp(block.timestamp + timestampAdvance);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    Escrowed Balance Checkpoint Tests
    //////////////////////////////////////////////////////////////*/

    function test_Escrowed_Balances_Checkpoints_Are_Updated() public {
        // stake
        stakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (uint256 ts, uint256 blk, uint256 value) =
            stakingRewardsV2.escrowedBalancesCheckpoints(address(this), 0);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, TEST_VALUE);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());

        // update block timestamp
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // unstake
        unstakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (ts, blk, value) = stakingRewardsV2.escrowedBalancesCheckpoints(address(this), 1);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, 0);
    }

    function test_Escrowed_Balances_Checkpoints_Updated_At_Same_Time() public {
        // stake
        stakeEscrowedFundsV2(address(this), TEST_VALUE * 2);

        // get last checkpoint
        (uint256 ts, uint256 blk, uint256 value) =
            stakingRewardsV2.escrowedBalancesCheckpoints(address(this), 0);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, TEST_VALUE * 2);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());

        // update block timestamp
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // unstake
        unstakeEscrowedFundsV2(address(this), TEST_VALUE);
        unstakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (ts, blk, value) = stakingRewardsV2.escrowedBalancesCheckpoints(address(this), 1);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, 0);
    }

    function test_Escrowed_Balances_Checkpoints_Are_Updated_Fuzz(
        uint32 maxAmountStaked,
        uint8 numberOfRounds
    ) public {
        vm.assume(maxAmountStaked > 0);
        // keep the number of rounds low to keep tests fast
        vm.assume(numberOfRounds < 50);

        // Stake and unstake in each iteration/round and check that the checkpoints are updated correctly
        for (uint8 i = 0; i < numberOfRounds; i++) {
            // get random values for each round
            uint256 amountToStake = getPseudoRandomNumber(maxAmountStaked, 1, i);
            uint256 amountToUnstake = getPseudoRandomNumber(amountToStake, 1, i);
            uint256 timestampAdvance = getPseudoRandomNumber(amountToUnstake, 0, i);

            // get initial values
            uint256 previousTotal = stakingRewardsV2.balanceOf(address(this));

            // stake
            stakeEscrowedFundsV2(address(this), amountToStake);

            // get last checkpoint
            uint256 length = stakingRewardsV2.escrowedBalancesCheckpointsLength(address(this));
            uint256 finalIndex = length == 0 ? 0 : length - 1;
            (uint256 ts, uint256 blk, uint256 value) =
                stakingRewardsV2.escrowedBalancesCheckpoints(address(this), finalIndex);

            // check checkpoint values
            assertEq(ts, block.timestamp);
            assertEq(blk, block.number);
            assertEq(value, previousTotal + amountToStake);

            // move beyond cold period
            vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());

            // update block timestamp
            vm.warp(block.timestamp + timestampAdvance);
            vm.roll(block.number + 1);

            // // unstake
            unstakeEscrowedFundsV2(address(this), amountToUnstake);

            // get last checkpoint
            uint256 newIndex = finalIndex + 1;
            (ts, blk, value) = stakingRewardsV2.escrowedBalancesCheckpoints(address(this), newIndex);

            // check checkpoint values
            assertEq(ts, block.timestamp);
            assertEq(blk, block.number);
            assertEq(value, previousTotal + amountToStake - amountToUnstake);

            // update block timestamp
            vm.warp(block.timestamp + timestampAdvance);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    Total Supply Checkpoint Tests
    //////////////////////////////////////////////////////////////*/

    function test_Total_Supply_Checkpoints_Are_Updated() public {
        // stake
        fundAccountAndStakeV2(address(this), TEST_VALUE);

        // get last checkpoint
        (uint256 ts, uint256 blk, uint256 value) = stakingRewardsV2.totalSupplyCheckpoints(0);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, TEST_VALUE);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());

        // update block timestamp
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // unstake
        stakingRewardsV2.unstake(TEST_VALUE);

        // get last checkpoint
        (ts, blk, value) = stakingRewardsV2.totalSupplyCheckpoints(1);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, 0);
    }

    function test_Total_Supply_Checkpoints_Updated_At_Same_Time() public {
        // stake
        fundAccountAndStakeV2(address(this), TEST_VALUE * 2);

        // get last checkpoint
        (uint256 ts, uint256 blk, uint256 value) = stakingRewardsV2.totalSupplyCheckpoints(0);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, TEST_VALUE * 2);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());

        // update block timestamp
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // unstake
        stakingRewardsV2.unstake(TEST_VALUE);
        stakingRewardsV2.unstake(TEST_VALUE);

        // get last checkpoint
        (ts, blk, value) = stakingRewardsV2.totalSupplyCheckpoints(1);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, 0);
    }

    function test_Total_Supply_Checkpoints_Are_Updated_Escrow_Staked() public {
        // stake
        stakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (uint256 ts, uint256 blk, uint256 value) = stakingRewardsV2.totalSupplyCheckpoints(0);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, TEST_VALUE);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());

        // update block timestamp
        vm.warp(block.timestamp + 1);
        vm.roll(block.number + 1);

        // unstake
        unstakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (ts, blk, value) = stakingRewardsV2.totalSupplyCheckpoints(1);

        // check values
        assertEq(ts, block.timestamp);
        assertEq(blk, block.number);
        assertEq(value, 0);
    }

    function test_Total_Supply_Checkpoints_Are_Updated_Fuzz(
        uint32 maxAmountStaked,
        uint8 numberOfRounds
    ) public {
        vm.assume(maxAmountStaked > 0);
        // keep the number of rounds low to keep tests fast
        vm.assume(numberOfRounds < 50);

        // Stake and unstake in each iteration/round and check that the checkpoints are updated correctly
        for (uint8 i = 0; i < numberOfRounds; i++) {
            // get random values for each round
            uint256 amountToStake = getPseudoRandomNumber(maxAmountStaked, 1, i);
            uint256 amountToUnstake = getPseudoRandomNumber(amountToStake, 1, i);
            uint256 timestampAdvance = getPseudoRandomNumber(amountToUnstake, 0, i);
            bool escrowStake = flipCoin(timestampAdvance);

            // get initial values
            uint256 previousTotal = stakingRewardsV2.balanceOf(address(this));

            // stake
            if (escrowStake) {
                stakeEscrowedFundsV2(address(this), amountToStake);
            } else {
                fundAccountAndStakeV2(address(this), amountToStake);
            }

            // get last checkpoint
            uint256 length = stakingRewardsV2.totalSupplyCheckpointsLength();
            uint256 finalIndex = length == 0 ? 0 : length - 1;
            (uint256 ts, uint256 blk, uint256 value) =
                stakingRewardsV2.totalSupplyCheckpoints(finalIndex);

            // check checkpoint values
            assertEq(ts, block.timestamp);
            assertEq(blk, block.number);
            assertEq(value, previousTotal + amountToStake);

            // move beyond cold period
            vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());

            // update block timestamp
            vm.warp(block.timestamp + timestampAdvance);
            vm.roll(block.number + 1);

            // unstake
            if (escrowStake) {
                unstakeEscrowedFundsV2(address(this), amountToUnstake);
            } else {
                stakingRewardsV2.unstake(amountToUnstake);
            }

            // get last checkpoint
            uint256 newIndex = finalIndex + 1;
            (ts, blk, value) = stakingRewardsV2.totalSupplyCheckpoints(newIndex);

            // check checkpoint values
            assertEq(ts, block.timestamp);
            assertEq(blk, block.number);
            assertEq(value, previousTotal + amountToStake - amountToUnstake);

            // update block timestamp
            vm.warp(block.timestamp + timestampAdvance);
        }
    }

    /*//////////////////////////////////////////////////////////////
                    Binary Search Balance Checkpoints
    //////////////////////////////////////////////////////////////*/

    function test_balanceAtTime() public {
        uint256 timestampToFind = 4;
        uint256 expectedValue;
        uint256 totalStaked;

        for (uint256 i = 0; i < 10; i++) {
            uint256 amount = TEST_VALUE * (i + 1);
            totalStaked += amount;
            if (timestampToFind == block.timestamp) {
                expectedValue = totalStaked;
            }
            fundAccountAndStakeV2(address(this), amount);
            vm.warp(block.timestamp + 1);
        }

        uint256 value = stakingRewardsV2.balanceAtTime(address(this), timestampToFind);

        assertEq(value, expectedValue);
    }

    function test_balanceAtTime_With_Unstake_Before_Block() public {
        uint256 timestampToFind = xCooldownPeriods(4);
        uint256 expectedValue;
        uint256 totalStaked;

        for (uint256 i = 0; i < 10; i++) {
            uint256 amount = TEST_VALUE;
            totalStaked += amount;
            if (block.timestamp == xCooldownPeriods(2)) {
                stakingRewardsV2.unstake(amount);
                totalStaked -= amount;
            }
            if (timestampToFind == block.timestamp) {
                expectedValue = totalStaked;
            }
            fundAccountAndStakeV2(address(this), amount);
            vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());
        }

        uint256 value = stakingRewardsV2.balanceAtTime(address(this), timestampToFind);

        assertEq(value, expectedValue);
    }

    function test_balanceAtTime_With_Unstake_After_Block() public {
        uint256 timestampToFind = xCooldownPeriods(4);
        uint256 expectedValue;
        uint256 totalStaked;

        for (uint256 i = 0; i < 10; i++) {
            uint256 amount = TEST_VALUE;
            totalStaked += amount;
            if (block.timestamp == xCooldownPeriods(5)) {
                stakingRewardsV2.unstake(amount);
                totalStaked -= amount;
            }
            if (timestampToFind == block.timestamp) {
                expectedValue = totalStaked;
            }
            fundAccountAndStakeV2(address(this), amount);
            vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());
        }

        uint256 value = stakingRewardsV2.balanceAtTime(address(this), timestampToFind);

        assertEq(value, expectedValue);
    }

    function test_balanceAtTime_With_Unstake_Before_And_After_Block() public {
        uint256 timestampToFind = xCooldownPeriods(4);
        uint256 expectedValue;
        uint256 totalStaked;

        for (uint256 i = 0; i < 10; i++) {
            uint256 amount = TEST_VALUE;
            totalStaked += amount;
            fundAccountAndStakeV2(address(this), amount);
            if (block.timestamp == xCooldownPeriods(2)) {
                vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());
                stakingRewardsV2.unstake(amount);
                stakingRewardsV2.unstake(amount);
                totalStaked -= amount;
                totalStaked -= amount;
            }
            if (block.timestamp == xCooldownPeriods(5)) {
                vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());
                stakingRewardsV2.unstake(amount);
                stakingRewardsV2.unstake(amount);
                stakingRewardsV2.unstake(amount);
                totalStaked -= amount;
                totalStaked -= amount;
                totalStaked -= amount;
            }
            if (timestampToFind == block.timestamp) {
                expectedValue = totalStaked;
            }
            vm.warp(block.timestamp + stakingRewardsV2.cooldownPeriod());
        }

        uint256 value = stakingRewardsV2.balanceAtTime(address(this), timestampToFind);
        assertEq(value, expectedValue);
    }

    function test_balanceAtTime_At_Each_Block() public {
        vm.warp(3);
        fundAccountAndStakeV2(address(this), 1);

        vm.warp(6);
        fundAccountAndStakeV2(address(this), 1);

        vm.warp(8);
        fundAccountAndStakeV2(address(this), 1);

        vm.warp(12);
        fundAccountAndStakeV2(address(this), 1);

        vm.warp(23);
        fundAccountAndStakeV2(address(this), 1);

        uint256 value;

        for (uint256 i = 0; i < 30; i++) {
            value = stakingRewardsV2.balanceAtTime(address(this), i);
            if (i < 3) {
                assertEq(value, 0);
            } else if (i < 6) {
                assertEq(value, 1);
            } else if (i < 8) {
                assertEq(value, 2);
            } else if (i < 12) {
                assertEq(value, 3);
            } else if (i < 23) {
                assertEq(value, 4);
            } else {
                assertEq(value, 5);
            }
        }
    }

    function test_balanceAtTime_Fuzz(uint256 timestampToFind, uint8 numberOfRounds) public {
        vm.assume(numberOfRounds < 50);
        vm.assume(timestampToFind > 0);

        uint256 expectedValue;
        uint256 totalStaked;
        bool notYetPassedBlock = true;

        for (uint256 i = 0; i < numberOfRounds; i++) {
            // get random values
            uint256 amount = getPseudoRandomNumber(1 ether, 1, timestampToFind);
            uint256 timestampAdvance = getPseudoRandomNumber(1000, 0, amount);

            // if we are at the block to find, set the expected value
            if (block.timestamp == timestampToFind) {
                expectedValue = totalStaked + amount;
                notYetPassedBlock = false;
                // otherwise if we just passed the block to find, set the expected value
            } else if (block.timestamp > timestampToFind && notYetPassedBlock) {
                expectedValue = totalStaked;
                notYetPassedBlock = false;
            }

            // stake funds
            fundAccountAndStakeV2(address(this), amount);
            totalStaked += amount;

            // don't advance the block if we are on the last round
            if (i != numberOfRounds - 1) {
                vm.warp(block.timestamp + timestampAdvance);
            }
        }

        uint256 value = stakingRewardsV2.balanceAtTime(address(this), timestampToFind);
        // if we are before the block to find, the expected value is the total staked
        if (timestampToFind > block.timestamp) {
            assertEq(value, totalStaked);
        } else {
            // otherwise, the expected value is the value at the block to find
            assertEq(value, expectedValue);
        }
    }

    /*//////////////////////////////////////////////////////////////
                Binary Search EscrowBalance Checkpoints
    //////////////////////////////////////////////////////////////*/

    function test_escrowbalanceAtTime() public {
        uint256 timestampToFind = 4;
        uint256 expectedValue;
        uint256 totalStaked;

        for (uint256 i = 0; i < 10; i++) {
            uint256 amount = TEST_VALUE * (i + 1);
            totalStaked += amount;
            if (timestampToFind == block.timestamp) {
                expectedValue = totalStaked;
            }
            stakeEscrowedFundsV2(address(this), amount);
            vm.warp(block.timestamp + 1);
        }

        uint256 value = stakingRewardsV2.escrowedBalanceAtTime(address(this), timestampToFind);

        assertEq(value, expectedValue);
    }

    function test_escrowbalanceAtTime_At_Each_Block() public {
        vm.warp(3);
        stakeEscrowedFundsV2(address(this), 1);

        vm.warp(6);
        stakeEscrowedFundsV2(address(this), 1);

        vm.warp(8);
        stakeEscrowedFundsV2(address(this), 1);

        vm.warp(12);
        stakeEscrowedFundsV2(address(this), 1);

        vm.warp(23);
        stakeEscrowedFundsV2(address(this), 1);

        uint256 value;

        for (uint256 i = 0; i < 30; i++) {
            value = stakingRewardsV2.escrowedBalanceAtTime(address(this), i);
            if (i < 3) {
                assertEq(value, 0);
            } else if (i < 6) {
                assertEq(value, 1);
            } else if (i < 8) {
                assertEq(value, 2);
            } else if (i < 12) {
                assertEq(value, 3);
            } else if (i < 23) {
                assertEq(value, 4);
            } else {
                assertEq(value, 5);
            }
        }
    }

    function test_escrowbalanceAtTime_Fuzz(uint256 timestampToFind, uint8 numberOfRounds) public {
        vm.assume(numberOfRounds < 50);
        vm.assume(timestampToFind > 0);

        uint256 expectedValue;
        uint256 totalStaked;
        bool notYetPassedBlock = true;

        for (uint256 i = 0; i < numberOfRounds; i++) {
            // get random values
            uint256 amount = getPseudoRandomNumber(1 ether, 1, timestampToFind);
            uint256 timestampAdvance = getPseudoRandomNumber(1000, 0, amount);

            // if we are at the block to find, set the expected value
            if (block.timestamp == timestampToFind) {
                expectedValue = totalStaked + amount;
                notYetPassedBlock = false;
                // otherwise if we just passed the block to find, set the expected value
            } else if (block.timestamp > timestampToFind && notYetPassedBlock) {
                expectedValue = totalStaked;
                notYetPassedBlock = false;
            }

            // stake funds
            stakeEscrowedFundsV2(address(this), amount);
            totalStaked += amount;

            // don't advance the block if we are on the last round
            if (i != numberOfRounds - 1) {
                vm.warp(block.timestamp + timestampAdvance);
            }
        }

        uint256 value = stakingRewardsV2.escrowedBalanceAtTime(address(this), timestampToFind);
        // if we are before the block to find, the expected value is the total staked
        if (timestampToFind > block.timestamp) {
            assertEq(value, totalStaked);
        } else {
            // otherwise, the expected value is the value at the block to find
            assertEq(value, expectedValue);
        }
    }

    /*//////////////////////////////////////////////////////////////
                Binary Search TotalSupply Checkpoints
    //////////////////////////////////////////////////////////////*/

    function test_totalSupplyAtTime() public {
        uint256 timestampToFind = 4;
        uint256 expectedValue;
        uint256 totalStaked;

        for (uint256 i = 0; i < 10; i++) {
            uint256 amount = TEST_VALUE * (i + 1);
            totalStaked += amount;
            if (timestampToFind == block.timestamp) {
                expectedValue = totalStaked;
            }
            if (flipCoin()) fundAccountAndStakeV2(address(this), amount);
            else stakeEscrowedFundsV2(address(this), amount);

            vm.warp(block.timestamp + 1);
        }

        uint256 value = stakingRewardsV2.totalSupplyAtTime(timestampToFind);
        assertEq(value, expectedValue);
    }

    function test_totalSupplyAtTime_Beyond_Max() public {
        fundAccountAndStakeV2(address(this), TEST_VALUE);
        vm.warp(block.timestamp + 1);
        fundAccountAndStakeV2(address(this), TEST_VALUE);
        vm.warp(block.timestamp + 1);
        fundAccountAndStakeV2(address(this), TEST_VALUE);
        vm.warp(block.timestamp + 1);
        fundAccountAndStakeV2(address(this), TEST_VALUE);
        vm.warp(block.timestamp + 1);
        fundAccountAndStakeV2(address(this), TEST_VALUE);
        vm.warp(block.timestamp + 1);

        uint256 value = stakingRewardsV2.totalSupplyAtTime(block.timestamp + 100);
        assertEq(value, TEST_VALUE * 5);
    }

    function test_totalSupplyAtTime_At_Each_Block() public {
        vm.warp(3);
        stakeEscrowedFundsV2(address(this), 1);

        vm.warp(6);
        fundAccountAndStakeV2(address(this), 1);

        vm.warp(8);
        stakeEscrowedFundsV2(address(this), 1);

        vm.warp(12);
        fundAccountAndStakeV2(address(this), 1);

        vm.warp(23);
        stakeEscrowedFundsV2(address(this), 1);

        uint256 value;

        for (uint256 i = 0; i < 30; i++) {
            value = stakingRewardsV2.totalSupplyAtTime(i);
            if (i < 3) {
                assertEq(value, 0);
            } else if (i < 6) {
                assertEq(value, 1);
            } else if (i < 8) {
                assertEq(value, 2);
            } else if (i < 12) {
                assertEq(value, 3);
            } else if (i < 23) {
                assertEq(value, 4);
            } else {
                assertEq(value, 5);
            }
        }
    }

    function test_totalSupplyAtTime_Fuzz(uint256 timestampToFind, uint8 numberOfRounds) public {
        vm.assume(numberOfRounds < 50);
        vm.assume(timestampToFind > 0);

        uint256 expectedValue;
        uint256 totalStaked;
        bool notYetPassedBlock = true;

        for (uint256 i = 0; i < numberOfRounds; i++) {
            // get random values
            uint256 amount = getPseudoRandomNumber(1 ether, 1, timestampToFind);
            uint256 timestampAdvance = getPseudoRandomNumber(1000, 0, amount);

            // if we are at the block to find, set the expected value
            if (block.timestamp == timestampToFind) {
                expectedValue = totalStaked + amount;
                notYetPassedBlock = false;
                // otherwise if we just passed the block to find, set the expected value
            } else if (block.timestamp > timestampToFind && notYetPassedBlock) {
                expectedValue = totalStaked;
                notYetPassedBlock = false;
            }

            // stake funds
            if (flipCoin()) {
                fundAccountAndStakeV2(address(this), amount);
            } else {
                stakeEscrowedFundsV2(address(this), amount);
            }
            totalStaked += amount;

            // don't advance the block if we are on the last round
            if (i != numberOfRounds - 1) {
                vm.warp(block.timestamp + timestampAdvance);
            }
        }

        uint256 value = stakingRewardsV2.totalSupplyAtTime(timestampToFind);
        // if we are before the block to find, the expected value is the total staked
        if (timestampToFind > block.timestamp) {
            assertEq(value, totalStaked);
        } else {
            // otherwise, the expected value is the value at the block to find
            assertEq(value, expectedValue);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                Helpers
    //////////////////////////////////////////////////////////////*/

    function xCooldownPeriods(uint256 numCooldowns) public view returns (uint256) {
        return 1 + (numCooldowns * stakingRewardsV2.cooldownPeriod());
    }
}
