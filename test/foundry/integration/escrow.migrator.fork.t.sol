// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "../utils/helpers/StakingTestHelpers.t.sol";
import {Migrate} from "../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {VestingEntries} from "../../../contracts/interfaces/IRewardEscrow.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {EscrowMigrator} from "../../../contracts/EscrowMigrator.sol";
import "../utils/Constants.t.sol";

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StakingV2MigrationForkTests is StakingTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address public owner;
    EscrowMigrator public escrowMigrator;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        vm.rollFork(106_878_447);

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

        // set owners address code to trick the test into allowing onlyOwner functions to be called via script
        vm.etch(owner, address(new Migrate()).code);

        (rewardEscrowV2, stakingRewardsV2,,) = Migrate(owner).runCompleteMigrationProcess({
            _owner: owner,
            _kwenta: address(kwenta),
            _supplySchedule: address(supplySchedule),
            _stakingRewardsV1: address(stakingRewardsV1),
            _treasuryDAO: treasury,
            _printLogs: false
        });

        // deploy migrator
        address migratorImpl = address(
            new EscrowMigrator(
            address(kwenta),
            address(rewardEscrowV1),
            address(rewardEscrowV2)
            )
        );

        escrowMigrator = EscrowMigrator(
            address(
                new ERC1967Proxy(
                    migratorImpl,
                    abi.encodeWithSignature("initialize(address)", owner)
                )
            )
        );

        vm.prank(owner);
        rewardEscrowV1.setTreasuryDAO(address(escrowMigrator));
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Migrator() public {
        uint256 escrowBalance = rewardEscrowV1.balanceOf(user1);
        assertEq(escrowBalance, 16.324711673459301166 ether);

        uint256 numVestingEntries = rewardEscrowV1.numVestingEntries(user1);
        assertEq(numVestingEntries, 16);

        entryIDs = rewardEscrowV1.getAccountVestingEntryIDs(user1, 0, numVestingEntries);
        assertEq(entryIDs.length, 16);

        (uint256 total, uint256 totalFee) = rewardEscrowV1.getVestingQuantity(user1, entryIDs);

        assertEq(total, 3_479_506_953_460_982_524);
        assertEq(totalFee, 12_845_204_719_998_318_642);

        // step 1
        vm.prank(user1);
        escrowMigrator.initiateMigration();

        // step 2
        vm.prank(user1);
        escrowMigrator.registerEntriesForVestingAndMigration(entryIDs);

        uint256 step2UserBalance = kwenta.balanceOf(user1);
        uint256 step2MigratorBalance = kwenta.balanceOf(address(escrowMigrator));

        // step 3.1 - vest
        vm.prank(user1);
        rewardEscrowV1.vest(entryIDs);

        uint256 step2UserBalanceAfterVest = kwenta.balanceOf(user1);
        uint256 step2MigratorBalanceAfterVest = kwenta.balanceOf(address(escrowMigrator));
        assertEq(step2UserBalanceAfterVest, step2UserBalance + total);
        assertEq(step2MigratorBalanceAfterVest, step2MigratorBalance + totalFee);

        // step 3.2 - confirm vest
        vm.prank(user1);
        escrowMigrator.confirmEntriesAreVested(entryIDs);

        // step 4 - pay for migration
        vm.prank(user1);
        kwenta.approve(address(escrowMigrator), total);
        vm.prank(user1);
        escrowMigrator.payForMigration();

        // step 5 - migrate entries
        // vm.prank(user1);
        // escrowMigrator.migrateRegisteredEntries(user1, entryIDs);




        // assertEq(rewardEscrowV1.balanceOf(user1), step2UserBalance + total);
    }
}
