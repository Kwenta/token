// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "../utils/helpers/StakingTestHelpers.t.sol";
import {Migrate} from "../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import "../utils/Constants.t.sol";

contract StakingV2MigrationForkTests is StakingTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public owner;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        vm.rollFork(OPTIMISM_BLOCK_NUMBER_JUST_AFTER_PAUSE);

        // define main contracts
        kwenta = Kwenta(OPTIMISM_KWENTA_TOKEN);
        rewardEscrowV1 = RewardEscrow(OPTIMISM_REWARD_ESCROW_V1);
        supplySchedule = SupplySchedule(OPTIMISM_SUPPLY_SCHEDULE);
        stakingRewardsV1 = StakingRewards(OPTIMISM_STAKING_REWARDS_V1);

        // define main addresses
        owner = OPTIMISM_PDAO;
        treasury = OPTIMISM_TREASURY_DAO;
        user1 = OPTIMISM_RANDOM_STAKING_USER;
        user2 = createUser();

        rewardEscrowV2 = RewardEscrowV2(OPTIMISM_REWARD_ESCROW_V2);
        stakingRewardsV2 = StakingRewardsV2(OPTIMISM_STAKING_REWARDS_V2);
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Roll_Back() public {
        // check contract is paused
        assertEq(stakingRewardsV2.paused(), true);

        // check correct owner is set
        assertEq(owner, stakingRewardsV2.owner());

        // upgrade staking v2 contract
        address stakingRewardsV2RollbackImpl = deployStakingRewardsV2RollbackImpl();
        vm.prank(owner);
        stakingRewardsV2.upgradeTo(stakingRewardsV2RollbackImpl);

        uint256 balanceBefore = kwenta.balanceOf(owner);

        // recover funds
        vm.prank(owner);
        stakingRewardsV2.recoverFundsForRollback(owner);

        uint256 balanceAfter = kwenta.balanceOf(owner);
        uint256 balanceRecovered = balanceAfter - balanceBefore;

        // allow ~1 ether difference as 0.7971 KWENTA was sent to staking rewards
        assertCloseTo(balanceRecovered, MINTED_TO_STAKING_REWARDS_V2, 1 ether);
        // make sure the recovered amount is less than the amount minted to staking rewards
        assertLt(balanceRecovered, MINTED_TO_STAKING_REWARDS_V2);
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function deployStakingRewardsV2RollbackImpl()
        internal
        returns (address stakingRewardsV2RollbackImpl)
    {
        stakingRewardsV2RollbackImpl = address(
            new StakingRewardsV2(
                address(kwenta),
                address(rewardEscrowV2),
                address(supplySchedule)
            )
        );
    }
}
