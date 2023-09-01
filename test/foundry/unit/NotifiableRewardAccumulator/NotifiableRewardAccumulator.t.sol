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

    function setUp() public override {
        super.setUp();
        notifiableRewardAccumulator.setStakingRewardsV2(address(stakingRewardsV2));
        vm.prank(treasury);
        kwenta.transfer(address(this), 100_000 ether);
        supplySchedule.setStakingRewards(address(notifiableRewardAccumulator));
    }

    function testNotifiableRewardAccumulatorMintSuccess() public {
        uint256 balanceBefore = kwenta.balanceOf(address(stakingRewardsV2));
        vm.warp(block.timestamp + 2 weeks);
        supplySchedule.mint();
        uint256 balanceAfter = kwenta.balanceOf(address(stakingRewardsV2));
        assertGt(balanceAfter, balanceBefore);
    }
}
