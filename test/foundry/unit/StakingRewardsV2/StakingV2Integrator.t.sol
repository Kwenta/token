// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/Test.sol";
import {IStakingRewardsV2} from "../../../../contracts/interfaces/IStakingRewardsV2.sol";
import {IStakingRewardsV2Integrator} from
    "../../../../contracts/interfaces/IStakingRewardsV2Integrator.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {MockStakingV2Integrator} from "../../utils/mocks/MockStakingV2Integrator.t.sol";
import "../../utils/Constants.t.sol";

contract StakingV2IntegratorTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    IStakingRewardsV2Integrator public integrator;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();

        integrator = new MockStakingV2Integrator(address(this));
        fundAccountAndStakeV2(address(integrator), 1 ether);
        createRewardEscrowEntryV2(address(integrator), 1 ether);

        fundAccountAndStakeV2(address(this), 1 ether);
        createRewardEscrowEntryV2(address(this), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                             ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function test_Beneficiary_Cannot_Be_Zero_Address() public {
        // setup bad integrator
        IStakingRewardsV2Integrator badIntegrator = new MockStakingV2Integrator(address(0));
        fundAccountAndStakeV2(address(badIntegrator), 1 ether);
        createRewardEscrowEntryV2(address(badIntegrator), 1 ether);
        assertEq(address(0), badIntegrator.beneficiary());

        // try to get rewards
        addNewRewards();
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.getIntegratorReward(address(badIntegrator));
    }

    function test_Beneficiary_Cannot_Steal_Funds() public {
        // try to get rewards
        addNewRewards();
        vm.prank(user1);
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.getIntegratorReward(address(integrator));
    }

    /*//////////////////////////////////////////////////////////////
                        CLAIM VIA CONTRACT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getIntegratorReward() public {
        // get starting balances
        uint256 entriesBefore = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceBefore = rewardEscrowV2.escrowedBalanceOf(address(this));

        // add new rewards
        addNewRewards();

        // get the rewards
        stakingRewardsV2.getIntegratorReward(address(integrator));

        // get ending balances
        uint256 entriesAfter = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceAfter = rewardEscrowV2.escrowedBalanceOf(address(this));

        // check balances updated correctly
        assertEq(entriesBefore + 1, entriesAfter);
        assertEq(balanceBefore + (1 weeks / 2), balanceAfter);
    }

    function test_getIntegratorReward_When_No_Rewards() public {
        // get starting balances
        uint256 entriesBefore = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceBefore = rewardEscrowV2.escrowedBalanceOf(address(this));

        // get the rewards
        stakingRewardsV2.getIntegratorReward(address(integrator));

        // get ending balances
        uint256 entriesAfter = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceAfter = rewardEscrowV2.escrowedBalanceOf(address(this));

        // check balances updated correctly
        assertEq(entriesBefore, entriesAfter);
        assertEq(balanceBefore, balanceAfter);
    }

    function test_Cannot_Use_Invalid_Integrator_Address() public {
        // add new rewards
        addNewRewards();

        // get the rewards
        vm.expectRevert();
        stakingRewardsV2.getIntegratorReward(createUser());
    }

    function test_Cannot_Use_When_Paused() public {
        // add new rewards
        addNewRewards();

        // pause the contract
        stakingRewardsV2.pauseStakingRewards();

        // get the rewards
        vm.expectRevert("Pausable: paused");
        stakingRewardsV2.getIntegratorReward(address(integrator));
    }

    /*//////////////////////////////////////////////////////////////
                  CLAIM INTEGRATOR AND SENDER REWARDS
    //////////////////////////////////////////////////////////////*/

    function test_getIntegratorAndSenderReward() public {
        // get starting balances
        uint256 entriesBefore = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceBefore = rewardEscrowV2.escrowedBalanceOf(address(this));

        // add new rewards
        addNewRewards();

        // get the rewards
        stakingRewardsV2.getIntegratorAndSenderReward(address(integrator));

        // get ending balances
        uint256 entriesAfter = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceAfter = rewardEscrowV2.escrowedBalanceOf(address(this));

        // check balances updated correctly
        assertEq(entriesBefore + 2, entriesAfter);
        assertEq(balanceBefore + 1 weeks, balanceAfter);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function addNewRewards() internal {
        // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
        addNewRewardsToStakingRewardsV2(1 weeks);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());
    }

    // TODO: think can getReward for contract and sender be merged into one escrow entry
    // TODO: test compound for contract and sender
    // TODO: possible get rid of _to and use msg.sender
}
