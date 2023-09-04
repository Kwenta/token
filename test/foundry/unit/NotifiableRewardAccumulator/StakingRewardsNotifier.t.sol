// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {IStakingRewardsNotifier} from "../../../../contracts/interfaces/IStakingRewardsNotifier.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsNotifier} from "../../../../contracts/StakingRewardsNotifier.sol";
import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";
import {StakingV2Setup} from "./StakingV2SetupWithAccumulator.t.sol";

contract StakingRewardsNotifierTest is StakingV2Setup {

    event RewardAdded(uint256 reward);

    function setUp() public override {
        super.setUp();
        stakingRewardsNotifier.setStakingRewardsV2(address(stakingRewardsV2));
        vm.prank(treasury);
        kwenta.transfer(address(this), 100_000 ether);
        supplySchedule.setStakingRewards(address(stakingRewardsNotifier));
    }

    function testNotifiableRewardAccumulatorCannotSetStakingV2Again() public {
        vm.expectRevert(IStakingRewardsNotifier.StakingRewardsV2IsSet.selector);
        stakingRewardsNotifier.setStakingRewardsV2(address(stakingRewardsV2));
    }

    function testNotifiableRewardAccumulatorCannotSetStakingV2To0() public {
        vm.expectRevert(IStakingRewardsNotifier.InputAddress0.selector);
        stakingRewardsNotifier.setStakingRewardsV2(address(0));
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
        kwenta.transfer(address(stakingRewardsNotifier), 1000 ether);
        vm.warp(block.timestamp + 1 weeks);
        uint256 balanceBefore = kwenta.balanceOf(address(stakingRewardsV2));
        vm.expectEmit(true, true, true, true);
        emit RewardAdded(mintAmount + 1000 ether);
        supplySchedule.mint();
        uint256 balanceAfter = kwenta.balanceOf(address(stakingRewardsV2));
        assertGt(balanceAfter, balanceBefore);
        assertEq(balanceAfter - balanceBefore, 1000 ether + mintAmount);
    }

    function testNotifiableRewardAccumulatorOnlySupplySchedule() public {
        vm.expectRevert(IStakingRewardsNotifier.OnlySupplySchedule.selector);
        stakingRewardsNotifier.notifyRewardAmount(1000 ether);
    }

    function testFuzzNotifiableRewardAccumulatorAddFunds(uint256 retroactive1, uint256 retroactive2, uint256 retroactive3) public {
        /// @dev this is so the user as enough funds to send
        vm.assume(retroactive1 < 30_000 ether);
        vm.assume(retroactive2 < 30_000 ether);
        vm.assume(retroactive3 < 30_000 ether);
        
        uint256 mintAmount = 17177543635384615384614;
        kwenta.transfer(address(stakingRewardsNotifier), retroactive1);
        vm.warp(block.timestamp + 1 weeks);
        kwenta.transfer(address(stakingRewardsNotifier), retroactive2);
        vm.warp(block.timestamp + 1 weeks);
        kwenta.transfer(address(stakingRewardsNotifier), retroactive3);
        uint256 balanceBefore = kwenta.balanceOf(address(stakingRewardsV2));
        vm.expectEmit(true, true, true, true);
        emit RewardAdded(mintAmount + retroactive1 + retroactive2 + retroactive3);
        supplySchedule.mint();

        uint256 balanceAfter = kwenta.balanceOf(address(stakingRewardsV2));
        assertGt(balanceAfter, balanceBefore);
        assertEq(balanceAfter - balanceBefore, retroactive1 + retroactive2 + retroactive3 + mintAmount);
    }

    //todo: change new migrate.s.sol

}
