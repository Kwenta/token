// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "../utils/helpers/StakingTestHelpers.t.sol";
import {Migrate} from "../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import "../utils/Constants.t.sol";

address constant STAKING_REWARDS_V2_OPTIMISM = 0xe5bB889B1f0B6B4B7384Bd19cbb37adBDDa941a6;
address constant REWARD_ESCROW_V2_OPTIMISM = 0xd5fE5beAa04270B32f81Bf161768c44DF9880D11;
address constant V1_STAKER = 0x2E95471Bef4c39fA8365d2592FBA7Cafe71a3722;

contract StakingV2MigrationForkTests is StakingTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public owner;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        vm.rollFork(106_849_977);

        // define main contracts
        kwenta = Kwenta(OPTIMISM_KWENTA_TOKEN);
        rewardEscrowV1 = RewardEscrow(OPTIMISM_REWARD_ESCROW_V1);
        supplySchedule = SupplySchedule(OPTIMISM_SUPPLY_SCHEDULE);
        stakingRewardsV1 = StakingRewards(OPTIMISM_STAKING_REWARDS_V1);

        // define main addresses
        owner = OPTIMISM_KWENTA_OWNER;
        treasury = OPTIMISM_TREASURY_DAO;
        user1 = OPTIMISM_RANDOM_STAKING_USER;
        user2 = createUser();
        user3 = createUser();

        // // set owners address code to trick the test into allowing onlyOwner functions to be called via script
        // vm.etch(owner, address(new Migrate()).code);

        stakingRewardsV2 = StakingRewardsV2(STAKING_REWARDS_V2_OPTIMISM);
        rewardEscrowV2 = RewardEscrowV2(REWARD_ESCROW_V2_OPTIMISM);

        // (rewardEscrowV2, stakingRewardsV2,,) = Migrate(owner).runCompleteMigrationProcess({
        //     _owner: owner,
        //     _kwenta: address(kwenta),
        //     _supplySchedule: address(supplySchedule),
        //     _stakingRewardsV1: address(stakingRewardsV1),
        //     _treasuryDAO: treasury,
        //     _printLogs: false
        // });
    }

    function test_Cannot_Cheat_StakingRewardsV2() public {
        checkCannotBeCheated();
    }

    function test_Cannot_Cheat_After_Upgrade() public {
        upgradeToStakingRewardsV3();
        checkCannotBeCheated();

    }

    function upgradeToStakingRewardsV3() public {
        address stakingRewardsV3Implementation = address(
            new StakingRewardsV2(
                address(kwenta),
                address(rewardEscrowV2),
                address(supplySchedule),
                address(stakingRewardsV1)
            )
        );

        vm.prank(OPTIMISM_PDAO);
        stakingRewardsV2.upgradeTo(stakingRewardsV3Implementation);
    }

    function checkCannotBeCheated() internal {
        fundAndApproveAccountV2(user2, 10 ether);
        fundAndApproveAccountV2(user3, 10 ether);

        uint256 user2Balance = kwenta.balanceOf(user2);
        assertEq(user2Balance, 10 ether);
        uint256 user3Balance = kwenta.balanceOf(user3);
        assertEq(user3Balance, 10 ether);

        uint256 earnedUser2 = stakingRewardsV2.earned(user2);
        assertEq(earnedUser2, 0);
        uint256 earnedUser3 = stakingRewardsV2.earned(user3);
        assertEq(earnedUser3, 0);

        stakeFundsV2(user2, 10 ether);

        earnedUser2 = stakingRewardsV2.earned(user2);
        assertEq(earnedUser2, 0);
        // earnedUser3 = stakingRewardsV2.earned(user2);
        // assertEq(earnedUser3, 0);

        // vm.warp(block.timestamp + 2 weeks);

        // stakeFundsV2(user3, 10 ether);

        // earnedUser2 = stakingRewardsV2.earned(user2);
        // assertEq(earnedUser2, 0.115818349662228630 ether);
        // earnedUser3 = stakingRewardsV2.earned(user3);
        // assertEq(earnedUser3, 0);
    }

    // forge test --fork-url $(grep ARCHIVE_NODE_URL_L2 .env | cut -d '=' -f2) --mt test_Reality -vv
    function test_Reality() public {
        uint256 v1TotalBalance = stakingRewardsV1.balanceOf(V1_STAKER);
        uint256 v1LiquidBalance = stakingRewardsV1.nonEscrowedBalanceOf(V1_STAKER);
        uint256 v1EscrowBalance = stakingRewardsV1.escrowedBalanceOf(V1_STAKER);

        assertEq(v1TotalBalance, 2418023079570933558512);
        assertEq(v1LiquidBalance, 2000000000000000000000);
        assertEq(v1EscrowBalance, 418023079570933558512);

        uint256 rewardsIfIClaimedOnV1Now = stakingRewardsV1.earned(V1_STAKER);
        assertEq(rewardsIfIClaimedOnV1Now, 0.553215035946112087 ether);

        uint256 rewardsIfIClaimedOnV2Now = stakingRewardsV2.earned(V1_STAKER);
        assertEq(rewardsIfIClaimedOnV2Now, 0.804148071201945672 ether);

        assertEq(332564266237127, stakingRewardsV2.rewardPerToken());
        assertEq(0, stakingRewardsV2.userRewardPerTokenPaid(V1_STAKER));

        vm.prank(V1_STAKER);
        stakingRewardsV1.unstake(v1LiquidBalance);

        // due to escrowed balance
        rewardsIfIClaimedOnV2Now = stakingRewardsV2.earned(V1_STAKER);
        assertEq(rewardsIfIClaimedOnV2Now, 0.139019538727691672 ether);


        vm.prank(V1_STAKER);
        rewardEscrowV1.unstakeEscrow(v1EscrowBalance);

        // due to no balance
        rewardsIfIClaimedOnV2Now = stakingRewardsV2.earned(V1_STAKER);
        assertEq(rewardsIfIClaimedOnV2Now, 0 ether);

        assertEq(332564266237127, stakingRewardsV2.rewardPerToken());
        assertEq(0, stakingRewardsV2.userRewardPerTokenPaid(V1_STAKER));

        vm.prank(V1_STAKER);
        kwenta.approve(address(stakingRewardsV2), v1LiquidBalance);
        vm.prank(V1_STAKER);
        stakingRewardsV2.stake(v1LiquidBalance);

        assertEq(332564266237127, stakingRewardsV2.rewardPerToken());
        assertEq(332564266237127, stakingRewardsV2.userRewardPerTokenPaid(V1_STAKER));

        uint256 balanceOnV2 = stakingRewardsV2.balanceOf(V1_STAKER);
        assertEq(balanceOnV2, v1LiquidBalance);

        rewardsIfIClaimedOnV2Now = stakingRewardsV2.earned(V1_STAKER);
        assertEq(rewardsIfIClaimedOnV2Now, 0 ether);

        // uint256 balanceOnV1 = stakingRewardsV2.v1BalanceOf(V1_STAKER);
        // uint256 balanceOnV2 = stakingRewardsV2.balanceOf(V1_STAKER);
        // console.log("balanceOnV1", balanceOnV1);
        // console.log("balanceOnV2", balanceOnV2);
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
        assertEq(user1StakedV1, stakingRewardsV2.v1BalanceOf(user1));
        assertEq(v1TotalSupply, stakingRewardsV2.v1TotalSupply());

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
        assertEq(stakingRewardsV2.v1BalanceOf(user1), user1EscrowStakedV1);
        assertEq(stakingRewardsV2.v1TotalSupply(), v1TotalSupply - user1NonEscrowStakedV1);
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
