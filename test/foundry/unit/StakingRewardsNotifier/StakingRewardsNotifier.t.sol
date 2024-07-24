// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {IStakingRewardsNotifier} from "../../../../contracts/interfaces/IStakingRewardsNotifier.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsNotifier} from "../../../../contracts/StakingRewardsNotifier.sol";
import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";

contract StakingRewardsNotifierTest is DefaultStakingV2Setup {
    event RewardAdded(uint256 reward, uint256 rewardUsdc);

    function setUp() public override {
        super.setUp();
        vm.prank(treasury);
        kwenta.transfer(address(this), 100_000 ether);
    }

    function testCannotDeployWithZeroOwnerAddress() public {
        vm.expectRevert(IStakingRewardsNotifier.ZeroAddress.selector);
        new StakingRewardsNotifier(address(0), address(kwenta), address(usdc), address(supplySchedule));
    }

    function testCannotDeployWithZeroKwentaAddress() public {
        vm.expectRevert(IStakingRewardsNotifier.ZeroAddress.selector);
        new StakingRewardsNotifier(address(this), address(0), address(usdc), address(supplySchedule));
    }

    function testCannotDeployWithZeroUsdcAddress() public {
        vm.expectRevert(IStakingRewardsNotifier.ZeroAddress.selector);
        new StakingRewardsNotifier(address(this), address(kwenta), address(0), address(supplySchedule));
    }

    function testCannotDeployWithZeroSupplyScheduleAddress() public {
        vm.expectRevert(IStakingRewardsNotifier.ZeroAddress.selector);
        new StakingRewardsNotifier(address(this), address(kwenta), address(usdc), address(0));
    }

    function testNotifiableRewardAccumulatorSetStakingV2OnlyOwner() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        rewardsNotifier.setStakingRewardsV2(address(stakingRewardsV2));
    }

    function testNotifiableRewardAccumulatorStakingV2Set() public {
        assertEq(address(rewardsNotifier.stakingRewardsV2()), address(stakingRewardsV2));
    }

    function testNotifiableRewardAccumulatorCannotSetStakingV2Twice() public {
        vm.prank(address(0));
        vm.expectRevert(IStakingRewardsNotifier.AlreadySet.selector);
        rewardsNotifier.setStakingRewardsV2(address(stakingRewardsV1));
    }

    function testNotifiableRewardAccumulatorCannotSetStakingV2To0() public {
        vm.prank(address(0));
        vm.expectRevert(IStakingRewardsNotifier.ZeroAddress.selector);
        rewardsNotifier.setStakingRewardsV2(address(0));
    }

    function testNotifiableRewardAccumulatorMintSuccess() public {
        uint256 mintAmount = 17_177_543_635_384_615_384_614;
        uint256 balanceBefore = kwenta.balanceOf(address(stakingRewardsV2));
        vm.warp(block.timestamp + 2 weeks);
        vm.expectEmit(true, true, true, true);
        emit RewardAdded(mintAmount, 0);
        supplySchedule.mint();
        uint256 balanceAfter = kwenta.balanceOf(address(stakingRewardsV2));
        assertGt(balanceAfter, balanceBefore);
    }

    function testNotifiableRewardAccumulatorRetroactiveFundsSuccess() public {
        uint256 mintAmount = 17_177_543_635_384_615_384_614;
        vm.warp(block.timestamp + 1 weeks);
        kwenta.transfer(address(rewardsNotifier), 1000 ether);
        vm.warp(block.timestamp + 1 weeks);
        uint256 balanceBefore = kwenta.balanceOf(address(stakingRewardsV2));
        assert(supplySchedule.isMintable());
        vm.expectEmit(true, true, true, true);
        emit RewardAdded(mintAmount + 1000 ether, 0);
        supplySchedule.mint();
        uint256 balanceAfter = kwenta.balanceOf(address(stakingRewardsV2));
        assertGt(balanceAfter, balanceBefore);
        assertEq(balanceAfter - balanceBefore, 1000 ether + mintAmount);
    }

    function testNotifiableRewardAccumulatorOnlySupplySchedule() public {
        vm.expectRevert(IStakingRewardsNotifier.OnlySupplySchedule.selector);
        rewardsNotifier.notifyRewardAmount(1000 ether);
    }

    function testFuzzNotifiableRewardAccumulatorAddFunds(
        uint256 retroactive1,
        uint256 retroactive2,
        uint256 retroactive3
    ) public {
        /// @dev this is so the user as enough funds to send
        vm.assume(retroactive1 < 30_000 ether);
        vm.assume(retroactive2 < 30_000 ether);
        vm.assume(retroactive3 < 30_000 ether);

        uint256 mintAmount = 17_177_543_635_384_615_384_614;
        kwenta.transfer(address(rewardsNotifier), retroactive1);
        vm.warp(block.timestamp + 1 weeks);
        kwenta.transfer(address(rewardsNotifier), retroactive2);
        vm.warp(block.timestamp + 1 weeks);
        kwenta.transfer(address(rewardsNotifier), retroactive3);
        uint256 balanceBefore = kwenta.balanceOf(address(stakingRewardsV2));
        vm.expectEmit(true, true, true, true);
        emit RewardAdded(mintAmount + retroactive1 + retroactive2 + retroactive3, 0);
        supplySchedule.mint();

        uint256 balanceAfter = kwenta.balanceOf(address(stakingRewardsV2));
        assertGt(balanceAfter, balanceBefore);
        assertEq(
            balanceAfter - balanceBefore, retroactive1 + retroactive2 + retroactive3 + mintAmount
        );
    }

    function testNotifiableRewardAccumulatorEarlyVest() public {
        /// @dev this is to remove setup ether
        kwenta.transfer(address(0x1), 100_000 ether);

        appendRewardEscrowEntryV2(address(this), 1000 ether);
        vm.warp(block.timestamp + 26 weeks);

        // check initial values
        (uint256 claimable, uint256 fee) = rewardEscrowV2.getVestingEntryClaimable(1);
        assertEq(claimable, 550 ether);
        assertEq(fee, 450 ether);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 1000 ether);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 1000 ether);
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);

        uint256 treasuryBalanceBefore = kwenta.balanceOf(treasury);

        entryIDs.push(1);
        rewardEscrowV2.vest(entryIDs);

        uint256 treasuryBalanceAfter = kwenta.balanceOf(treasury);
        uint256 treasuryReceived = treasuryBalanceAfter - treasuryBalanceBefore;

        // 22.5% should go to the treasury
        assertEq(treasuryReceived, 225 ether);

        // 22.5% should go to RewardsNotifier
        assertEq(kwenta.balanceOf(address(rewardsNotifier)), 225 ether);

        // 55% should go to the staker
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 550 ether);
        assertEq(kwenta.balanceOf(address(this)), 550 ether);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 0);

        // Nothing should be left in reward escrow
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 0);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 0);
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 0);

        // Mint and the RewardsNotifier should transfer amounts to the staking contract
        uint256 mintAmount = 176268972686291953380981;
        uint256 balanceBefore = kwenta.balanceOf(address(stakingRewardsV2));
        supplySchedule.mint();
        uint256 balanceAfter = kwenta.balanceOf(address(stakingRewardsV2));
        assertGt(balanceAfter, balanceBefore);
        assertEq(balanceAfter - balanceBefore, 225 ether + mintAmount);

    }
}
