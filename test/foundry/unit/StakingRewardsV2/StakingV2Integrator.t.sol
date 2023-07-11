// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/Test.sol";
import {IStakingRewardsV2} from "../../../../contracts/interfaces/IStakingRewardsV2.sol";
import {IStakingRewardsV2Integrator} from
    "../../../../contracts/interfaces/IStakingRewardsV2Integrator.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {MockStakingV2Integrator} from "../../utils/mocks/MockStakingV2Integrator.t.sol";
import {MaliciousStakingV2Integrator} from "../../utils/mocks/MaliciousStakingV2Integrator.t.sol";
import "../../utils/Constants.t.sol";

contract StakingV2IntegratorTests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    IStakingRewardsV2Integrator public integrator;
    IStakingRewardsV2Integrator public maliciousIntegrator;

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();

        maliciousIntegrator = IStakingRewardsV2Integrator(
            address(new MaliciousStakingV2Integrator(address(this), address(stakingRewardsV2)))
        );

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
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.getIntegratorAndSenderReward(address(badIntegrator));
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.getIntegratorRewardAndCompound(address(badIntegrator));
    }

    function test_Beneficiary_Cannot_Steal_Funds() public {
        // try to get rewards
        addNewRewards();
        vm.prank(user1);
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.getIntegratorReward(address(integrator));
    }

    function test_Beneficiary_Cannot_Steal_Funds_Via_getIntegratorAndSenderReward() public {
        // try to get rewards
        addNewRewards();
        vm.prank(user1);
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.getIntegratorAndSenderReward(address(integrator));
    }

    function test_Beneficiary_Cannot_Steal_Funds_Via_getIntegratorRewardAndCompound() public {
        // try to get rewards
        addNewRewards();
        vm.prank(user1);
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        stakingRewardsV2.getIntegratorRewardAndCompound(address(integrator));
    }

    /*//////////////////////////////////////////////////////////////
                        CLAIM VIA CONTRACT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getIntegratorReward() public {
        // get starting balances
        uint256 entriesBefore = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceBefore = rewardEscrowV2.escrowedBalanceOf(address(this));
        uint256 stakedBalanceBefore = stakingRewardsV2.balanceOf(address(this));

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

        // check didn't compound
        assertEq(stakingRewardsV2.balanceOf(address(this)), stakedBalanceBefore);
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
        uint256 stakedBalanceBefore = stakingRewardsV2.balanceOf(address(this));

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

        // check didn't compound
        assertEq(stakingRewardsV2.balanceOf(address(this)), stakedBalanceBefore);
    }

    function test_getIntegratorAndSenderReward_When_No_Rewards() public {
        // get starting balances
        uint256 entriesBefore = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceBefore = rewardEscrowV2.escrowedBalanceOf(address(this));

        // get the rewards
        stakingRewardsV2.getIntegratorAndSenderReward(address(integrator));

        // get ending balances
        uint256 entriesAfter = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceAfter = rewardEscrowV2.escrowedBalanceOf(address(this));

        // check balances updated correctly
        assertEq(entriesBefore, entriesAfter);
        assertEq(balanceBefore, balanceAfter);
    }

    function test_Cannot_Use_Invalid_Integrator_Address_getIntegratorAndSenderReward() public {
        // add new rewards
        addNewRewards();

        // get the rewards
        vm.expectRevert();
        stakingRewardsV2.getIntegratorAndSenderReward(createUser());
    }

    function test_Cannot_Use_getIntegratorAndSenderReward_When_Paused() public {
        // add new rewards
        addNewRewards();

        // pause the contract
        stakingRewardsV2.pauseStakingRewards();

        // get the rewards
        vm.expectRevert("Pausable: paused");
        stakingRewardsV2.getIntegratorAndSenderReward(address(integrator));
    }

    /*//////////////////////////////////////////////////////////////
                           CLAIM AND COMPOUND
    //////////////////////////////////////////////////////////////*/

    function test_getIntegratorRewardAndCompound() public {
        // get starting balances
        uint256 entriesBefore = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceBefore = rewardEscrowV2.escrowedBalanceOf(address(this));

        // add new rewards
        addNewRewards();

        // get the rewards
        stakingRewardsV2.getIntegratorRewardAndCompound(address(integrator));

        // get ending balances
        uint256 entriesAfter = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceAfter = rewardEscrowV2.escrowedBalanceOf(address(this));

        // check balances updated correctly
        assertEq(entriesBefore + 2, entriesAfter);
        assertEq(balanceBefore + 1 weeks, balanceAfter);
        assertEq(stakingRewardsV2.escrowedBalanceOf(address(this)), balanceAfter);
    }

    function test_getIntegratorRewardAndCompound_When_No_Rewards() public {
        // get starting balances
        uint256 entriesBefore = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceBefore = rewardEscrowV2.escrowedBalanceOf(address(this));

        // get the rewards
        stakingRewardsV2.getIntegratorRewardAndCompound(address(integrator));

        // get ending balances
        uint256 entriesAfter = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceAfter = rewardEscrowV2.escrowedBalanceOf(address(this));

        // check balances updated correctly
        assertEq(entriesBefore, entriesAfter);
        assertEq(balanceBefore, balanceAfter);
        assertEq(stakingRewardsV2.escrowedBalanceOf(address(this)), balanceAfter);
    }

    function test_Cannot_Use_Invalid_Integrator_Address_getIntegratorRewardAndCompound() public {
        // add new rewards
        addNewRewards();

        // get the rewards
        vm.expectRevert();
        stakingRewardsV2.getIntegratorRewardAndCompound(createUser());
    }

    function test_Cannot_Use_getIntegratorRewardAndCompound_When_Paused() public {
        // add new rewards
        addNewRewards();

        // pause the contract
        stakingRewardsV2.pauseStakingRewards();

        // get the rewards
        vm.expectRevert("Pausable: paused");
        stakingRewardsV2.getIntegratorRewardAndCompound(address(integrator));
    }

    /*//////////////////////////////////////////////////////////////
                           REENTRANCY CHECKS
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Reenter_getIntegratorReward() public {
        fundAccountAndStakeV2(address(maliciousIntegrator), 1 ether);
        createRewardEscrowEntryV2(address(maliciousIntegrator), 1 ether);

        // add new rewards
        addNewRewards();

        // get the rewards
        // should fail due to "EvmError: StateChangeDuringStaticCall" but the error isn't bubbled back
        vm.expectRevert();
        stakingRewardsV2.getIntegratorReward(address(maliciousIntegrator));
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
}
