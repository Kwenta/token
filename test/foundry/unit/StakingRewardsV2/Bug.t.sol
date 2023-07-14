// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {IStakingRewardsV2} from "../../../../contracts/interfaces/IStakingRewardsV2.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {IERC20} from "../../../../contracts/interfaces/IERC20.sol";
import "../../utils/Constants.t.sol";

contract Bug is DefaultStakingV2Setup {
    function setUp() public override {
        super.setUp();

        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV2), INITIAL_SUPPLY / 4);

        address sc = address(stakingRewardsV2.supplySchedule());
        vm.prank(sc);
        stakingRewardsV2.notifyRewardAmount(TEST_VALUE);
    }

    function test_Expected() public {
        fundAccountAndStakeV2(user1, 10 ether);

        vm.warp(block.timestamp + 2 weeks);

        vm.prank(user1);
        stakingRewardsV2.unstake(10 ether);
        
        uint reward = stakingRewardsV2.rewards(user1);
        assert(reward > 0);
    }

    function test_Actual() public {
        fundAccountAndStakeV1(user1, 10 ether);

        vm.warp(block.timestamp + 1 weeks);

        vm.prank(user1);
        stakingRewardsV1.unstake(10 ether);

        uint reward = stakingRewardsV2.rewards(user1);
        assert(reward > 0);
    }

}