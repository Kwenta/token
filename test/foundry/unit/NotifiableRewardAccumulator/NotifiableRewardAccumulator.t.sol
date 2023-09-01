// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "../../../../lib/forge-std/src/console.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {NotifiableRewardAccumulator} from "../../../../contracts/NotifiableRewardAccumulator.sol";
import {StakingV2Setup} from "./StakingV2SetupWithAccumulator.t.sol";

contract NotifiableRewardAccumulatorTest is StakingV2Setup {

    event RewardAdded(uint256 reward);

    function setUp() public override {
        super.setUp();
        notifiableRewardAccumulator.setStakingRewardsV2(address(stakingRewardsV2));
        vm.prank(treasury);
        kwenta.transfer(address(this), 100_000 ether);
        supplySchedule.setStakingRewards(address(notifiableRewardAccumulator));
    }

    function testNotifiableRewardAccumulatorCannotSetStakingV2Again() public {
        vm.expectRevert(NotifiableRewardAccumulator.StakingRewardsV2IsSet.selector);
        notifiableRewardAccumulator.setStakingRewardsV2(address(stakingRewardsV2));
    }

    function testNotifiableRewardAccumulatorMintSuccess() public {
        uint256 mintAmount = 17177543635384615384614;
        uint256 balanceBefore = kwenta.balanceOf(address(stakingRewardsV2));
        vm.warp(block.timestamp + 2 weeks);
        vm.expectEmit(true, true, true, true);
        emit RewardAdded(mintAmount);
        supplySchedule.mint();
        uint256 balanceAfter = kwenta.balanceOf(address(stakingRewardsV2));
        assertGt(balanceAfter, balanceBefore);
    }

    function testNotifiableRewardAccumulatorRetroactiveFundsSuccess() public {
        uint256 mintAmount = 17177543635384615384614;
        vm.warp(block.timestamp + 1 weeks);
        kwenta.transfer(address(notifiableRewardAccumulator), 1000 ether);
        vm.warp(block.timestamp + 1 weeks);
        uint256 balanceBefore = kwenta.balanceOf(address(stakingRewardsV2));
        vm.expectEmit(true, true, true, true);
        emit RewardAdded(mintAmount + 1000 ether);
        supplySchedule.mint();
        uint256 balanceAfter = kwenta.balanceOf(address(stakingRewardsV2));
        assertGt(balanceAfter, balanceBefore);
        assertEq(balanceAfter - balanceBefore, 1000 ether + mintAmount);
    }
}
