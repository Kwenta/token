// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "../utils/helpers/StakingTestHelpers.t.sol";
import {Migrate} from "../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {OldStakingRewardsV2} from "./interfaces/OldStakingRewardsV2.sol";
import {IOldStakingRewardsNotifier} from "./interfaces/IOldStakingRewardsNotifier.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import "../utils/Constants.t.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract StakingV2MigrationForkTests is StakingTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    OldStakingRewardsV2 oldStakingRewardsV2;
    IOldStakingRewardsNotifier oldStakingRewardsNotifier;
    RewardEscrowV2 rewardEscrowV2fork;
    IERC20 usdcFork;

    function setUp() public override {
        vm.rollFork(110_553_170);

        // define main contracts
        kwenta = Kwenta(OPTIMISM_KWENTA_TOKEN);
        usdcFork = IERC20(OPTIMISM_USDC_TOKEN);
        rewardEscrowV1 = RewardEscrow(OPTIMISM_REWARD_ESCROW_V1);
        rewardEscrowV2fork = RewardEscrowV2(OPTIMISM_REWARD_ESCROW_V2);
        supplySchedule = SupplySchedule(OPTIMISM_SUPPLY_SCHEDULE);
        oldStakingRewardsV2 = OldStakingRewardsV2(OPTIMISM_STAKING_REWARDS_V2);
        oldStakingRewardsNotifier = IOldStakingRewardsNotifier(OPTIMISM_STAKING_REWARDS_NOTIFIER);

        // define main addresses
        owner = OPTIMISM_PDAO;
        treasury = OPTIMISM_TREASURY_DAO;
        user1 = OPTIMISM_RANDOM_STAKING_USER_1;

        // set owners address code to trick the test into allowing onlyOwner functions to be called via script
        vm.etch(owner, address(new Migrate()).code);

        (rewardEscrowV2, stakingRewardsV2, escrowMigrator, rewardsNotifier) = Migrate(owner)
            .runCompleteMigrationProcess({
            _owner: owner,
            _kwenta: address(kwenta),
            _usdc: address(usdcFork),
            _supplySchedule: address(supplySchedule),
            _treasuryDAO: treasury,
            _rewardEscrowV1: address(rewardEscrowV1),
            _printLogs: false
        });
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Upgrade_StakingRewardsV2_To_DualRewards() public {
        uint256 intialStakedV2 = oldStakingRewardsV2.balanceOf(address(this));
        assertEq(intialStakedV2, 0);

        vm.prank(treasury);
        kwenta.transfer(address(this), TEST_VALUE);
        kwenta.approve(address(oldStakingRewardsV2), TEST_VALUE);

        oldStakingRewardsV2.stake(TEST_VALUE);
        assertEq(oldStakingRewardsV2.balanceOf(address(this)), TEST_VALUE);

        // initial escrow balance
        uint256 initialEscrowBalance = rewardEscrowV2fork.escrowedBalanceOf(address(this));

        // configure reward rate
        vm.prank(address(oldStakingRewardsNotifier));
        oldStakingRewardsV2.notifyRewardAmount(TEST_VALUE);

        // fast forward 2 weeks
        vm.warp(block.timestamp + 2 weeks);

        // get reward
        oldStakingRewardsV2.getReward();

        // check reward escrow balance increased
        uint256 escrowBalance = rewardEscrowV2fork.escrowedBalanceOf(address(this));
        assertGt(escrowBalance, initialEscrowBalance);

        uint256 earnedKwenta = oldStakingRewardsV2.earned(address(this));

        address stakingRewardsV3Implementation = address(
            new StakingRewardsV2(
                address(kwenta),
                address(usdcFork),
                address(rewardEscrowV2fork),
                address(oldStakingRewardsNotifier)
            )
        );

        vm.prank(owner);
        oldStakingRewardsV2.upgradeTo(address(stakingRewardsV3Implementation));
        StakingRewardsV2 newV2Impl = StakingRewardsV2(address(oldStakingRewardsV2));

        assertEq(oldStakingRewardsV2.balanceOf(address(this)), TEST_VALUE);

        // configure reward rate
        vm.prank(address(oldStakingRewardsNotifier));
        newV2Impl.notifyRewardAmount(TEST_VALUE, TEST_VALUE);

        // fast forward 2 weeks
        vm.warp(block.timestamp + 2 weeks);

        // check some stake has been earned
        assertGt(newV2Impl.earned(address(this)), earnedKwenta);
        assertGt(newV2Impl.earnedUSDC(address(this)) , 0);
    }
}
