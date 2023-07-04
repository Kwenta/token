// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {console} from "forge-std/Test.sol";
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
                        CLAIM VIA CONTRACT TESTS
    //////////////////////////////////////////////////////////////*/

    function test_getRewardOnBehalfOfIntegrator() public {
        // send in 604800 (1 week) of rewards - (using 1 week for round numbers)
        addNewRewardsToStakingRewardsV2(1 weeks);

        // fast forward 1 week - one complete period
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());
        vm.warp(block.timestamp + stakingRewardsV2.rewardsDuration());

        // get starting balances
        uint256 entriesBefore = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceBefore = rewardEscrowV2.escrowedBalanceOf(address(this));

        // get the rewards
        stakingRewardsV2.getRewardOnBehalfOfIntegrator(address(integrator), address(this));

        // get ending balances
        uint256 entriesAfter = rewardEscrowV2.balanceOf(address(this));
        uint256 balanceAfter = rewardEscrowV2.escrowedBalanceOf(address(this));

        // check balances updated correctly
        assertEq(entriesBefore + 1, entriesAfter);
        assertEq(balanceBefore + 1 weeks, balanceAfter);
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
