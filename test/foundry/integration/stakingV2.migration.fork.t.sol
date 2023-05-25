// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import {StakingTestHelpers} from "../utils/StakingTestHelpers.t.sol";
import {Migrate} from "../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import "../utils/Constants.t.sol";

contract StakingV2MigrationForkTests is StakingTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    address public owner;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        vm.rollFork(BLOCK_NUMBER);

        // define main contracts
        kwenta = Kwenta(KWENTA);
        rewardEscrowV1 = RewardEscrow(REWARD_ESCROW_V1);
        supplySchedule = SupplySchedule(SUPPLY_SCHEDULE);
        stakingRewardsV1 = StakingRewards(STAKING_REWARDS_V1);

        // define main addresses
        owner = KWENTA_OWNER;
        treasury = TREASURY_DAO;
        user1 = RANDOM_STAKING_USER;

        // set owners address code to trick the test into allowing onlyOwner functions to be called via script
        vm.etch(owner, address(new Migrate()).code);

        (rewardEscrowV2, stakingRewardsV2,,) = Migrate(owner).runCompleteMigrationProcess({
            _owner: owner,
            _kwenta: address(kwenta),
            _supplySchedule: address(supplySchedule),
            _stakingRewardsV1: address(stakingRewardsV1),
            _treasuryDAO: treasury,
            _printLogs: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                                 TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Migrate_Then_Move_Funds_From_V1_To_V2_And_Generate_New_Rewards() public {
        uint256 user1StakedV1 = stakingRewardsV1.balanceOf(user1);
        uint256 user1EscrowStakedV1 = stakingRewardsV1.escrowedBalanceOf(user1);
        uint256 user1NonEscrowStakedV1 = stakingRewardsV1.nonEscrowedBalanceOf(user1);
        uint256 user1Earned = stakingRewardsV1.earned(user1);
        uint256 user1EscrowV1 = rewardEscrowV1.balanceOf(user1);
        uint256 initialBalance = kwenta.balanceOf(user1);

        // Check user1 has non-zero values
        assertGt(user1StakedV1, 0);
        assertGt(user1EscrowStakedV1, 0);
        assertGt(user1NonEscrowStakedV1, 0);
        assertGt(user1Earned, 0);
        assertGt(user1EscrowV1, 0);

        // unstake funds from v1
        exitStakingV1(user1);

        // check balances updated correctly
        assertEq(stakingRewardsV1.balanceOf(user1), user1EscrowStakedV1);
        assertEq(stakingRewardsV1.nonEscrowedBalanceOf(user1), 0);
        assertEq(stakingRewardsV1.earned(user1), 0);
        assertEq(kwenta.balanceOf(user1), initialBalance + user1NonEscrowStakedV1);
        assertEq(rewardEscrowV1.balanceOf(user1), user1EscrowV1 + user1Earned);

        // check initial v2 state
        assertEq(stakingRewardsV2.balanceOf(user1), 0);
        assertEq(stakingRewardsV2.earned(user1), 0);
        assertEq(stakingRewardsV2.nonEscrowedBalanceOf(user1), 0);
        assertEq(stakingRewardsV2.escrowedBalanceOf(user1), 0);
        assertEq(stakingRewardsV2.totalSupply(), 0);
        assertEq(rewardEscrowV2.totalEscrowBalanceOf(user1), 0);

        user1EscrowV1 = rewardEscrowV1.balanceOf(user1);

        // stake funds with v2
        stakeFundsV2(user1, kwenta.balanceOf(user1));

        // mint via supply schedule
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);
        warpAndMint(2 weeks);

        // get rewards
        getStakingRewardsV2(user1);

        // stake the rewards
        stakeAllUnstakedEscrowV2(user1);

        // check StakingRewardsV1 balance unchanged
        assertEq(stakingRewardsV1.nonEscrowedBalanceOf(user1), 0);
        assertEq(stakingRewardsV1.escrowedBalanceOf(user1), user1EscrowStakedV1);
        assertEq(stakingRewardsV1.balanceOf(user1), user1EscrowStakedV1);

        // check RewardEscrowV1 balance unchanged
        assertEq(rewardEscrowV1.balanceOf(user1), user1EscrowV1);

        uint256 user1EscrowStakedV2 = stakingRewardsV2.escrowedBalanceOf(user1);
        uint256 user1NonEscrowedStakeV2 = stakingRewardsV2.nonEscrowedBalanceOf(user1);

        // assert v2 rewards have been earned
        assertGt(rewardEscrowV2.totalEscrowBalanceOf(user1), 0);
        // v2 staked balance is equal to escrowed + non-escrowed balance
        assertEq(stakingRewardsV2.balanceOf(user1), user1EscrowStakedV2 + user1NonEscrowedStakeV2);
        // v2 reward escrow balance is equal to escrow staked balance
        assertEq(rewardEscrowV2.totalEscrowBalanceOf(user1), user1EscrowStakedV2);
    }
}
