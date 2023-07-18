// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;

import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";
import {IStakingRewardsV2} from "../../../../contracts/interfaces/IStakingRewardsV2.sol";
import {SupplySchedule} from "../../../../contracts/SupplySchedule.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {Test} from "../../../../lib/forge-std/src/Test.sol";

address constant KWENTA = 0x920Cf626a271321C151D027030D5d08aF699456b;
address constant STAKING_REWARDS_V2_IMPLEMENTATION = 0x33B725a1B2dE9178121D423D2A1c062C5452f310;
address constant STAKING_REWARDS_V2_PROXY = 0xe5bB889B1f0B6B4B7384Bd19cbb37adBDDa941a6;
address constant REWARD_ESCROW_V2_IMPLEMENTATION = 0xF877315CfC91E69e7f4c308ec312cf91D66a095F;
address constant REWARD_ESCROW_V2_PROXY = 0xd5fE5beAa04270B32f81Bf161768c44DF9880D11;
address constant SUPPLY_SCHEDULE = 0x3e8b82326Ff5f2f10da8CEa117bD44343ccb9c26;
address constant DAO = 0xe826d43961a87fBE71C91d9B73F7ef9b16721C07;
address constant EOA = 0x43BA2b95e19b441d04b22fAd2Adc250C4acEC305;
uint256 constant TEST_AMOUNT = 10_000 ether;
uint256 constant ONE_YEAR = 52 weeks;

// BLOCK_NUMBER corresponds to Jul-12-2023 05:35:23 PM +UTC
uint256 constant BLOCK_NUMBER = 106_792_273;

contract UpgradeRewardEscrowV2Test is Test {
    // contracts
    RewardEscrowV2 private rewardEscrowV3;
    RewardEscrowV2 private rewardEscrowProxy;

    /*//////////////////////////////////////////////////////////////
                            SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        vm.rollFork(BLOCK_NUMBER);
        rewardEscrowProxy = RewardEscrowV2(REWARD_ESCROW_V2_PROXY);
        // deploy V3 implementation
        rewardEscrowV3 = new RewardEscrowV2(KWENTA);
    }

    /*//////////////////////////////////////////////////////////////
                            TESTS
    //////////////////////////////////////////////////////////////*/

    /// @notice make sure the factory upgraded to the new implementation
    function testUpgradedImplementationAddress() public {
        // upgrade
        vm.prank(DAO);
        rewardEscrowProxy.upgradeTo(address(rewardEscrowV3));
        assertTrue(address(rewardEscrowV3) != REWARD_ESCROW_V2_IMPLEMENTATION);
    }

    /// @notice make sure the state did not change from the upgrade
    function testUpgrade() public {
        // record state prior to upgrade
        IStakingRewardsV2 stakingRewards = rewardEscrowProxy.stakingRewards();
        address treasuryDAO = rewardEscrowProxy.treasuryDAO();
        // VestingEntry memory entry = VestingEntry({
        //     escrowAmount: rewardEscrowProxy.vestingSchedules(0).escrowAmount,
        //     duration: rewardEscrowProxy.vestingSchedules(0).duration,
        //     endTime: rewardEscrowProxy.vestingSchedules(0).endTime,
        //     earlyVestingFee: rewardEscrowProxy.vestingSchedules(0)
        //         .earlyVestingFee
        // });
        uint nextEntryId = rewardEscrowProxy.nextEntryId();
        uint totalEscrowedAccountBalance = rewardEscrowProxy
            .totalEscrowedAccountBalance(EOA);
        uint totalVestedAccountBalance = rewardEscrowProxy
            .totalVestedAccountBalance(EOA);
        uint totalEscrowedBalance = rewardEscrowProxy.totalEscrowedBalance();
        // address earlyVestFeeDistributor = rewardEscrowProxy
        //     .earlyVestFeeDistributor();

        // upgrade
        vm.prank(DAO);
        rewardEscrowProxy.upgradeTo(address(rewardEscrowV3));
        assertTrue(address(rewardEscrowV3) != REWARD_ESCROW_V2_IMPLEMENTATION);
        RewardEscrowV2 upgradedRewardEscrow = RewardEscrowV2(
            REWARD_ESCROW_V2_PROXY
        );

        // check state did not change
        assertTrue(stakingRewards == upgradedRewardEscrow.stakingRewards());        
        // assertEq(treasuryDAO, rewardEscrowProxy.treasuryDAO());
        // assertEq(
        //     entry.amount,
        //     rewardEscrowProxy.vestingSchedules(0).amount
        // );
        assertEq(nextEntryId, rewardEscrowProxy.nextEntryId());
        assertEq(
            totalEscrowedAccountBalance,
            rewardEscrowProxy.totalEscrowedAccountBalance(EOA)
        );
        assertEq(
            totalVestedAccountBalance,
            rewardEscrowProxy.totalVestedAccountBalance(EOA)
        );
        assertEq(
            totalEscrowedBalance,
            rewardEscrowProxy.totalEscrowedBalance()
        );
        // assertEq(
        //     earlyVestFeeDistributor,
        //     rewardEscrowProxy.earlyVestFeeDistributor()
        // );
    }
}
