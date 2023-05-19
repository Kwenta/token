// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../utils/DefaultStakingV2Setup.t.sol";
import "../utils/Constants.t.sol";

contract StakingV2CheckpointingTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                        Balance Checkpoint Tests
    //////////////////////////////////////////////////////////////*/

    function test_Balances_Checkpoints_Are_Updated() public {
        // stake
        fundAccountAndStakeV2(address(this), TEST_VALUE);

        // get last checkpoint
        (uint256 blockTimestamp, uint256 value) = stakingRewardsV2.balances(address(this), 0);

        // check values
        assertEq(blockTimestamp, block.timestamp);
        assertEq(value, TEST_VALUE);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());

        // update block number
        vm.warp(block.timestamp + 1);

        // unstake
        stakingRewardsV2.unstake(TEST_VALUE);

        // get last checkpoint
        (blockTimestamp, value) = stakingRewardsV2.balances(address(this), 1);

        // check values
        assertEq(blockTimestamp, block.timestamp);
        assertEq(value, 0);
    }

    function test_Balances_Checkpoints_Are_Updated_Escrow_Staking() public {
        // stake
        stakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (uint256 blockTimestamp, uint256 value) = stakingRewardsV2.balances(address(this), 0);

        // check values
        assertEq(blockTimestamp, block.timestamp);
        assertEq(value, TEST_VALUE);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());

        // update block number
        vm.warp(block.timestamp + 1);

        // unstake
        unstakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (blockTimestamp, value) = stakingRewardsV2.balances(address(this), 1);

        // check values
        assertEq(blockTimestamp, block.timestamp);
        assertEq(value, 0);
    }

    // function test_Balances_Checkpoints_Are_Updated_Fuzz(uint32 maxAmountStaked, uint8 numberOfRounds) public {
    function test_Balances_Checkpoints_Are_Updated_Fuzz() public {
        uint32 maxAmountStaked = 2;
        uint8 numberOfRounds = 2;

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
            uint256 length = stakingRewardsV2.balancesLength(address(this));
            uint256 finalIndex = length == 0 ? 0 : length - 1;
            (uint256 blockTimestamp, uint256 value) = stakingRewardsV2.balances(address(this), finalIndex);

            // check checkpoint values
            assertEq(blockTimestamp, block.timestamp);
            assertEq(value, previousTotal + amountToStake);

            // move beyond cold period
            vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());

            // update block number
            vm.warp(block.timestamp + timestampAdvance);

            // unstake
            stakingRewardsV2.unstake(amountToUnstake);

            // get last checkpoint
            uint256 newIndex = finalIndex + 1;
            (blockTimestamp, value) = stakingRewardsV2.balances(address(this), newIndex);

            // check checkpoint values
            assertEq(blockTimestamp, block.timestamp);
            assertEq(value, previousTotal + amountToStake - amountToUnstake);

            // update block number
            vm.warp(block.timestamp + timestampAdvance);
        }
    }

    function test_Balances_Checkpoints_Are_Updated_Escrow_Staked_Fuzz(uint32 maxAmountStaked, uint8 numberOfRounds) public {
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
            uint256 length = stakingRewardsV2.balancesLength(address(this));
            uint256 finalIndex = length == 0 ? 0 : length - 1;
            (uint256 blockTimestamp, uint256 value) = stakingRewardsV2.balances(address(this), finalIndex);

            // check checkpoint values
            assertEq(blockTimestamp, block.timestamp);
            assertEq(value, previousTotal + amountToStake);

            // move beyond cold period
            vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());

            // update block number
            vm.warp(block.timestamp + timestampAdvance);

            // unstake
            unstakeEscrowedFundsV2(address(this), amountToUnstake);

            // get last checkpoint
            uint256 newIndex = finalIndex  + 1;
            (blockTimestamp, value) = stakingRewardsV2.balances(address(this), newIndex);

            // check checkpoint values
            assertEq(blockTimestamp, block.timestamp);
            assertEq(value, previousTotal + amountToStake - amountToUnstake);

            // update block number
            vm.warp(block.timestamp + timestampAdvance);
        }
    }

    // TODO: add tests for checkpoints updating in the same second

    /*//////////////////////////////////////////////////////////////
                    Escrowed Balance Checkpoint Tests
    //////////////////////////////////////////////////////////////*/

    function test_Escrowed_Balances_Checkpoints_Are_Updated() public {
        // stake
        stakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (uint256 blockTimestamp, uint256 value) = stakingRewardsV2.escrowedBalances(address(this), 0);

        // check values
        assertEq(blockTimestamp, block.timestamp);
        assertEq(value, TEST_VALUE);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());

        // update block number
        vm.warp(block.timestamp + 1);

        // unstake
        unstakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (blockTimestamp, value) = stakingRewardsV2.escrowedBalances(address(this), 1);

        // check values
        assertEq(blockTimestamp, block.timestamp);
        assertEq(value, 0);
    }

    function test_Escrowed_Balances_Checkpoints_Are_Updated_Fuzz(uint32 maxAmountStaked, uint8 numberOfRounds) public {
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
            uint256 length = stakingRewardsV2.escrowedBalancesLength(address(this));
            uint256 finalIndex = length == 0 ? 0 : length - 1;
            (uint256 blockTimestamp, uint256 value) = stakingRewardsV2.escrowedBalances(address(this), finalIndex);

            // check checkpoint values
            assertEq(blockTimestamp, block.timestamp);
            assertEq(value, previousTotal + amountToStake);

            // move beyond cold period
            vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());

            // update block number
            vm.warp(block.timestamp + timestampAdvance);

            // // unstake
            unstakeEscrowedFundsV2(address(this), amountToUnstake);

            // get last checkpoint
            uint256 newIndex = finalIndex + 1;
            (blockTimestamp, value) = stakingRewardsV2.escrowedBalances(address(this), newIndex);

            // check checkpoint values
            assertEq(blockTimestamp, block.timestamp);
            assertEq(value, previousTotal + amountToStake - amountToUnstake);

            // update block number
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
        (uint256 blockTimestamp, uint256 value) = stakingRewardsV2._totalSupply(0);

        // check values
        assertEq(blockTimestamp, block.timestamp);
        assertEq(value, TEST_VALUE);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());

        // update block number
        vm.warp(block.timestamp + 1);

        // unstake
        stakingRewardsV2.unstake(TEST_VALUE);

        // get last checkpoint
        (blockTimestamp, value) = stakingRewardsV2._totalSupply(1);

        // check values
        assertEq(blockTimestamp, block.timestamp);
        assertEq(value, 0);
    }

    function test_Total_Supply_Checkpoints_Are_Updated_Escrow_Staked() public {
        // stake
        stakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (uint256 blockTimestamp, uint256 value) = stakingRewardsV2._totalSupply(0);

        // check values
        assertEq(blockTimestamp, block.timestamp);
        assertEq(value, TEST_VALUE);

        // move beyond cold period
        vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());

        // update block number
        vm.warp(block.timestamp + 1);

        // unstake
        unstakeEscrowedFundsV2(address(this), TEST_VALUE);

        // get last checkpoint
        (blockTimestamp, value) = stakingRewardsV2._totalSupply(1);

        // check values
        assertEq(blockTimestamp, block.timestamp);
        assertEq(value, 0);
    }

    function test_Total_Supply_Checkpoints_Are_Updated_Fuzz(uint32 maxAmountStaked, uint8 numberOfRounds) public {
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
            uint256 length = stakingRewardsV2.totalSupplyLength();
            uint256 finalIndex = length == 0 ? 0 : length - 1;
            (uint256 blockTimestamp, uint256 value) = stakingRewardsV2._totalSupply(finalIndex);

            // check checkpoint values
            assertEq(blockTimestamp, block.timestamp);
            assertEq(value, previousTotal + amountToStake);

            // move beyond cold period
            vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());

            // update block number
            vm.warp(block.timestamp + timestampAdvance);

            // unstake
            if (escrowStake) {
                unstakeEscrowedFundsV2(address(this), amountToUnstake);
            } else {
                stakingRewardsV2.unstake(amountToUnstake);
            }

            // get last checkpoint
            uint256 newIndex = finalIndex + 1;
            (blockTimestamp, value) = stakingRewardsV2._totalSupply(newIndex);

            // check checkpoint values
            assertEq(blockTimestamp, block.timestamp);
            assertEq(value, previousTotal + amountToStake - amountToUnstake);

            // update block number
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
            vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());
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
            vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());
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
                vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());
                stakingRewardsV2.unstake(amount);
                stakingRewardsV2.unstake(amount);
                totalStaked -= amount;
                totalStaked -= amount;
            }
            if (block.timestamp == xCooldownPeriods(5)) {
                vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());
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
            vm.warp(block.timestamp + stakingRewardsV2.unstakingCooldownPeriod());
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
            if (i != numberOfRounds - 1) vm.warp(block.timestamp + timestampAdvance);
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

        uint256 value = stakingRewardsV2.escrowedbalanceAtTime(address(this), timestampToFind);

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
            value = stakingRewardsV2.escrowedbalanceAtTime(address(this), i);
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
            if (i != numberOfRounds - 1) vm.warp(block.timestamp + timestampAdvance);
        }

        uint256 value = stakingRewardsV2.escrowedbalanceAtTime(address(this), timestampToFind);
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

    function test_totalSupplyAtT() public {
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

        uint256 value = stakingRewardsV2.totalSupplyAtT(timestampToFind);
        assertEq(value, expectedValue);
    }

    function test_totalSupplyAtT_At_Each_Block() public {
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
            value = stakingRewardsV2.totalSupplyAtT(i);
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

    function test_totalSupplyAtT_Fuzz(uint256 timestampToFind, uint8 numberOfRounds) public {
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
            if (i != numberOfRounds - 1) vm.warp(block.timestamp + timestampAdvance);
        }

        uint256 value = stakingRewardsV2.totalSupplyAtT(timestampToFind);
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
        return 1 + (numCooldowns * stakingRewardsV2.unstakingCooldownPeriod());
    }

}
