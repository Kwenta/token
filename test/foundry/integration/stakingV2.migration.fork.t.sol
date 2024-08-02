// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "../utils/helpers/StakingTestHelpers.t.sol";
import {Migrate} from "../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import "../utils/Constants.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract StakingV2MigrationForkTests is StakingTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        vm.rollFork(OPTIMISM_BLOCK_NUMBER);

        // define main contracts
        kwenta = Kwenta(OPTIMISM_KWENTA_TOKEN);
        IERC20 usdc = IERC20(OPTIMISM_USDC_TOKEN);
        rewardEscrowV1 = RewardEscrow(OPTIMISM_REWARD_ESCROW_V1);
        supplySchedule = SupplySchedule(OPTIMISM_SUPPLY_SCHEDULE);
        stakingRewardsV1 = StakingRewards(OPTIMISM_STAKING_REWARDS_V1);

        // define main addresses
        owner = OPTIMISM_KWENTA_OWNER;
        treasury = OPTIMISM_TREASURY_DAO;
        user1 = OPTIMISM_RANDOM_STAKING_USER_1;
        user2 = createUser();

        // set owners address code to trick the test into allowing onlyOwner functions to be called via script
        vm.etch(owner, address(new Migrate()).code);

        (rewardEscrowV2, stakingRewardsV2, escrowMigrator, rewardsNotifier) = Migrate(
            owner
        ).runCompleteMigrationProcess({
            _owner: owner,
            _kwenta: address(kwenta),
            _usdc: address(usdc),
            _supplySchedule: address(supplySchedule),
            _treasuryDAO: treasury,
            _rewardEscrowV1: address(rewardEscrowV1),
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
        uint256 v1TotalSupply = stakingRewardsV1.totalSupply();
        uint256 initialBalance = kwenta.balanceOf(user1);

        // Check user1 has non-zero values
        assertGt(user1StakedV1, 0);
        assertGt(user1EscrowStakedV1, 0);
        assertGt(user1NonEscrowStakedV1, 0);
        assertGt(user1Earned, 0);
        assertGt(user1EscrowV1, 0);

        // check v2 state before unstaking
        assertEq(user1StakedV1, stakingRewardsV1.balanceOf(user1));
        assertEq(v1TotalSupply, stakingRewardsV1.totalSupply());

        // unstake funds from v1
        exitStakingV1(user1);

        // check balances updated correctly
        assertEq(stakingRewardsV1.balanceOf(user1), user1EscrowStakedV1);
        assertEq(stakingRewardsV1.nonEscrowedBalanceOf(user1), 0);
        assertEq(stakingRewardsV1.earned(user1), 0);
        assertEq(stakingRewardsV1.totalSupply(), v1TotalSupply - user1NonEscrowStakedV1);
        assertEq(kwenta.balanceOf(user1), initialBalance + user1NonEscrowStakedV1);
        assertEq(rewardEscrowV1.balanceOf(user1), user1EscrowV1 + user1Earned);

        // check initial v2 state
        assertEq(stakingRewardsV2.balanceOf(user1), 0);
        assertEq(stakingRewardsV2.earned(user1), 0);
        assertEq(stakingRewardsV2.nonEscrowedBalanceOf(user1), 0);
        assertEq(stakingRewardsV2.escrowedBalanceOf(user1), 0);
        assertEq(stakingRewardsV2.totalSupply(), 0);
        assertEq(rewardEscrowV2.escrowedBalanceOf(user1), 0);

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
        assertGt(rewardEscrowV2.escrowedBalanceOf(user1), 0);
        // v2 staked balance is equal to escrowed + non-escrowed balance
        assertEq(stakingRewardsV2.balanceOf(user1), user1EscrowStakedV2 + user1NonEscrowedStakeV2);
        // v2 reward escrow balance is equal to escrow staked balance
        assertEq(rewardEscrowV2.escrowedBalanceOf(user1), user1EscrowStakedV2);
    }

    function test_Create_Entry_After_Migration() public {
        createRewardEscrowEntryV2(user2, TEST_VALUE, 52 weeks);
        assertEq(rewardEscrowV2.balanceOf(user2), 1);
        assertEq(rewardEscrowV2.escrowedBalanceOf(user2), TEST_VALUE);
    }

    function test_Cannot_Create_Entry_After_Migration_Without_Approval() public {
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(user2);
        rewardEscrowV2.createEscrowEntry(user2, TEST_VALUE, 52 weeks, 90);
    }

    function test_Can_Vest_After_Migration() public {
        createRewardEscrowEntryV2(user2, TEST_VALUE, 52 weeks);
        uint256 treasuryBalanceBefore = kwenta.balanceOf(treasury);
        entryIDs.push(1);
        vm.prank(user2);
        rewardEscrowV2.vest(entryIDs);

        // check user got some funds
        assertGt(kwenta.balanceOf(user2), 0);

        // check treasury got some funds
        uint256 treasuryBalanceAfter = kwenta.balanceOf(treasury);
        assertGt(treasuryBalanceAfter, treasuryBalanceBefore);
    }

    function test_Cannot_Vest_If_Treasury_Transfer_Fails() public {
        createRewardEscrowEntryV2(user2, TEST_VALUE, 52 weeks);
        entryIDs.push(1);
        vm.prank(user2);

        // empty the treasury to force the transfer to fail
        uint256 rewardEscrowV2Balance = kwenta.balanceOf(address(rewardEscrowV2));
        vm.prank(address(rewardEscrowV2));
        kwenta.transfer(address(user1), rewardEscrowV2Balance);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(user2);
        rewardEscrowV2.vest(entryIDs);
    }

    function test_Cannot_Vest_If_Vested_Tokes_Transfer_Fails() public {
        createRewardEscrowEntryV2(user2, 2 ether, 52 weeks, 50);
        entryIDs.push(1);
        vm.prank(user2);

        // leave only 1 ether in the treasury, so the treasury transfer passes
        // but the user transfer fails
        uint256 rewardEscrowV2Balance = kwenta.balanceOf(address(rewardEscrowV2));
        vm.prank(address(rewardEscrowV2));
        kwenta.transfer(address(user1), rewardEscrowV2Balance - 1 ether);

        vm.expectRevert("ERC20: transfer amount exceeds balance");
        vm.prank(user2);
        rewardEscrowV2.vest(entryIDs);
    }
}
