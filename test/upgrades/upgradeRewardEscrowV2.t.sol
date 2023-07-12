// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {RewardEscrowV2} from "../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../contracts/StakingRewardsV2.sol";
import {SupplySchedule} from "../../contracts/SupplySchedule.sol";
import {Kwenta} from "../../contracts/Kwenta.sol";
import {Test} from "../../lib/forge-std/src/Test.sol";

address constant KWENTA = 0xDA0C33402Fc1e10d18c532F0Ed9c1A6c5C9e386C;
address constant STAKING_REWARDS_V2_IMPLEMENTATION = 0xE0aD43191312D6220DE64aFA54dbdD6982991A87;
address constant STAKING_REWARDS_V2_PROXY = 0x3e5371D909Bf1996c95e9D179b0Bc91C26fb1279;
address constant REWARD_ESCROW_V2_IMPLEMENTATION = 0x0A34aee61770b3cE293Fb17CfC9d4a7F70945260;
address constant REWARD_ESCROW_V2_PROXY = 0xf211F298C6985fF4cF6f9488e065292B818163F8;
address constant SUPPLY_SCHEDULE = 0x671423b2e8a99882FD14BbD07e90Ae8B64A0E63A;
address constant DAO = 0xC2ecD777d06FFDF8B3179286BEabF52B67E9d991;
address constant EOA = 0x42f9134E9d3Bf7eEE1f8A5Ac2a4328B059E7468c;
uint256 constant TEST_AMOUNT = 10_000 ether;
uint256 constant ONE_YEAR = 52 weeks;

// BLOCK_NUMBER corresponds to Jul-12-2023 02:16:54 PM +UTC
uint256 constant BLOCK_NUMBER = 11_871_673;

contract VestingUpgradeTest is Test {
    // contracts
    RewardEscrowV2 public rewardEscrowV3;

    struct VestingEntry {
        // The amount of KWENTA stored in this vesting entry
        uint256 escrowAmount;
        // The length of time until the entry is fully matured
        uint256 duration;
        // The time at which the entry will be fully matured
        uint64 endTime;
        // The percentage fee for vesting immediately
        // The actual penalty decreases linearly with time until it reaches 0 at block.timestamp=endTime
        uint8 earlyVestingFee;
    }

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);
        // deploy V3 implementation
        rewardEscrowV3 = new RewardEscrowV2();
    }

    /*//////////////////////////////////////////////////////////////
                            TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice make sure the factory upgraded to the new implementation
    function testUpgradedImplementationAddress() public {
        // upgrade
        vm.prank(DAO);
        REWARD_ESCROW_V2_PROXY.upgradeTo(address(rewardEscrowV3));
        assertEq(
            REWARD_ESCROW_V2_PROXY.implementation(),
            address(rewardEscrowV3)
        );
        assertTrue(address(rewardEscrowV3) != REWARD_ESCROW_V2_IMPLEMENTATION);
    }

    /// @notice make sure the state did not change from the upgrade
    function testUpgrade() public {
        // record state prior to upgrade
        uint maxDuration = REWARD_ESCROW_V2_PROXY.MAX_DURATION();
        uint defaultDuration = REWARD_ESCROW_V2_PROXY.DEFAULT_DURATION();
        uint defaultEarlyVestingFee = REWARD_ESCROW_V2_PROXY
            .DEFAULT_EARLY_VESTING_FEE();
        uint maximumEarlyVestingFee = REWARD_ESCROW_V2_PROXY
            .MAXIMUM_EARLY_VESTING_FEE();
        uint minimumEarlyVestingFee = REWARD_ESCROW_V2_PROXY
            .MINIMUM_EARLY_VESTING_FEE();
        StakingRewardsV2 stakingRewards = REWARD_ESCROW_V2_PROXY
            .stakingRewards();
        address treasuryDAO = REWARD_ESCROW_V2_PROXY.treasuryDAO();
        VestingEntry memory entry = REWARD_ESCROW_V2_PROXY.vestingSchedules(0);
        uint nextEntryId = REWARD_ESCROW_V2_PROXY.nextEntryId();
        uint totalEscrowedAccountBalance = REWARD_ESCROW_V2_PROXY
            .totalEscrowedAccountBalance(EOA);
        uint totalVestedAccountBalance = REWARD_ESCROW_V2_PROXY
            .totalVestedAccountBalance(EOA);
        uint totalEscrowedBalance = REWARD_ESCROW_V2_PROXY
            .totalEscrowedBalance();
        address earlyVestFeeDistributor = REWARD_ESCROW_V2_PROXY
            .earlyVestFeeDistributor();

        // upgrade
        vm.prank(DAO);
        REWARD_ESCROW_V2_PROXY.upgradeTo(address(rewardEscrowV3));
        assertEq(
            REWARD_ESCROW_V2_PROXY.implementation(),
            address(rewardEscrowV3)
        );
        assertTrue(address(rewardEscrowV3) != REWARD_ESCROW_V2_IMPLEMENTATION);

        // check state did not change
        assertEq(maxDuration, REWARD_ESCROW_V2_PROXY.MAX_DURATION());
        assertEq(defaultDuration, REWARD_ESCROW_V2_PROXY.DEFAULT_DURATION());
        assertEq(
            defaultEarlyVestingFee,
            REWARD_ESCROW_V2_PROXY.DEFAULT_EARLY_VESTING_FEE()
        );
        assertEq(
            maximumEarlyVestingFee,
            REWARD_ESCROW_V2_PROXY.MAXIMUM_EARLY_VESTING_FEE()
        );
        assertEq(
            minimumEarlyVestingFee,
            REWARD_ESCROW_V2_PROXY.MINIMUM_EARLY_VESTING_FEE()
        );
        assertEq(
            address(stakingRewards),
            REWARD_ESCROW_V2_PROXY.stakingRewards()
        );
        assertEq(treasuryDAO, REWARD_ESCROW_V2_PROXY.treasuryDAO());
        assertEq(
            entry.amount,
            REWARD_ESCROW_V2_PROXY.vestingSchedules(0).amount
        );
        assertEq(nextEntryId, REWARD_ESCROW_V2_PROXY.nextEntryId());
        assertEq(
            totalEscrowedAccountBalance,
            REWARD_ESCROW_V2_PROXY.totalEscrowedAccountBalance(EOA)
        );
        assertEq(
            totalVestedAccountBalance,
            REWARD_ESCROW_V2_PROXY.totalVestedAccountBalance(EOA)
        );
        assertEq(
            totalEscrowedBalance,
            REWARD_ESCROW_V2_PROXY.totalEscrowedBalance()
        );
        assertEq(
            earlyVestFeeDistributor,
            REWARD_ESCROW_V2_PROXY.earlyVestFeeDistributor()
        );
    }
}
