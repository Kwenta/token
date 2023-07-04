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
        stakingRewardsV2.getRewardOnBehalfOfIntegrator(address(badIntegrator), address(this));
    }

    function test_Beneficiary_Cannot_Steal_Funds() public {
        // try to get rewards
        addNewRewards();
        vm.expectRevert(IStakingRewardsV2.NotApproved.selector);
        vm.prank(user1);
        stakingRewardsV2.getRewardOnBehalfOfIntegrator(address(integrator), user1);
    }

    /*//////////////////////////////////////////////////////////////
                        CLAIM VIA CONTRACT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getRewardOnBehalfOfIntegrator() public {
        // get starting balances
        uint256 entriesBefore = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceBefore = rewardEscrowV2.escrowedBalanceOf(address(this));

        // add new rewards
        addNewRewards();

        // get the rewards
        stakingRewardsV2.getRewardOnBehalfOfIntegrator(address(integrator), address(this));

        // get ending balances
        uint256 entriesAfter = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceAfter = rewardEscrowV2.escrowedBalanceOf(address(this));

        // check balances updated correctly
        assertEq(entriesBefore + 1, entriesAfter);
        assertEq(balanceBefore + 1 weeks, balanceAfter);
    }

    function test_getRewardOnBehalfOfIntegrator_Via_Operator() public {
        stakingRewardsV2.approveOperator(user1, true);

        // get starting balances
        uint256 entriesBefore = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceBefore = rewardEscrowV2.escrowedBalanceOf(address(this));

        // add new rewards
        addNewRewards();

        // get the rewards
        vm.prank(user1);
        stakingRewardsV2.getRewardOnBehalfOfIntegrator(address(integrator), address(this));

        // get ending balances
        uint256 entriesAfter = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceAfter = rewardEscrowV2.escrowedBalanceOf(address(this));

        // check balances updated correctly
        assertEq(entriesBefore + 1, entriesAfter);
        assertEq(balanceBefore + 1 weeks, balanceAfter);
    }

    function test_getRewardOnBehalfOfIntegrator_Can_Send_Funds_Elsewhere() public {
        // get starting balances
        uint256 entriesBefore = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceBefore = rewardEscrowV2.escrowedBalanceOf(address(this));
        uint256 user1EntriesBefore = rewardEscrowV2.balanceOf(user1);
        uint256 user1BalanceBefore = rewardEscrowV2.escrowedBalanceOf(user1);

        // add new rewards
        addNewRewards();

        // get the rewards
        stakingRewardsV2.getRewardOnBehalfOfIntegrator(address(integrator), user1);

        // get ending balances
        uint256 entriesAfter = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceAfter = rewardEscrowV2.escrowedBalanceOf(address(this));
        uint256 user1EntriesAfter = rewardEscrowV2.balanceOf(user1);
        uint256 user1BalanceAfter = rewardEscrowV2.escrowedBalanceOf(user1);

        // check balances updated correctly
        assertEq(entriesBefore, entriesAfter);
        assertEq(balanceBefore, balanceAfter);
        assertEq(user1EntriesBefore + 1, user1EntriesAfter);
        assertEq(user1BalanceBefore + 1 weeks, user1BalanceAfter);
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

    // TODO: test InvalidBeneficiary
    // TODO: test via operator
    // TODO: test invalid operator
    // TODO: test invalid contract
    // TODO: test different _to addresses
    // TODO: test getReward for contract and sender
    // TODO: think can getReward for contract and sender be merged into one escrow entry
    // TODO: test compound for contract and sender
}
