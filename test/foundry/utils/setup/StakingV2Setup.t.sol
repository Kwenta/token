// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Test.sol";
import {Migrate} from "../../../../scripts/Migrate.s.sol";
import {StakingV1Setup} from "../../utils/setup/StakingV1Setup.t.sol";
import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";
import {EscrowMigrator} from "../../../../contracts/EscrowMigrator.sol";
import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";
import {StakingRewardsNotifier} from "../../../../contracts/StakingRewardsNotifier.sol";
import {IRewardEscrowV2} from "../../../../contracts/interfaces/IRewardEscrowV2.sol";
import "../../utils/Constants.t.sol";

contract StakingV2Setup is StakingV1Setup {
    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event RewardsDurationUpdated(uint256 newDuration);
    event CooldownPeriodUpdated(uint256 cooldownPeriod);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event OperatorApproved(address owner, address operator, bool approved);
    event RewardPaid(address indexed account, uint256 reward);
    event EscrowStaked(address indexed user, uint256 amount);
    event Vested(address indexed beneficiary, uint256 value);
    event VestingEntryCreated(
        address indexed beneficiary,
        uint256 value,
        uint256 duration,
        uint256 entryID,
        uint256 earlyVestingFee
    );
    event TreasuryDAOSet(address treasuryDAO);
    event StakingRewardsSet(address stakingRewards);
    event EarlyVestFeeSent(uint256 amountToTreasury, uint256 amountToNotifier);
    event EscrowMigratorSet(address escrowMigrator);

    /*//////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    RewardEscrowV2 internal rewardEscrowV2;
    StakingRewardsV2 internal stakingRewardsV2;
    EscrowMigrator internal escrowMigrator;
    StakingRewardsNotifier internal rewardsNotifier;
    Migrate internal migrate;

    address rewardEscrowV2Implementation;
    address stakingRewardsV2Implementation;
    address escrowMigratorImplementation;

    /*//////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        // Setup StakingV1
        super.setUp();

        // Deploy StakingV2
        migrate = new Migrate();
        (bool deploymentSuccess, bytes memory deploymentData) = address(migrate).delegatecall(
            abi.encodeWithSelector(
                migrate.deploySystem.selector,
                address(this),
                address(kwenta),
                address(usdc),
                address(supplySchedule),
                address(rewardEscrowV1),
                treasury,
                false
            )
        );
        require(deploymentSuccess, "Migrate.deploySystem failed");
        (
            rewardEscrowV2,
            stakingRewardsV2,
            escrowMigrator,
            rewardsNotifier,
            rewardEscrowV2Implementation,
            stakingRewardsV2Implementation,
            escrowMigratorImplementation
        ) = abi.decode(
            deploymentData,
            (
                RewardEscrowV2,
                StakingRewardsV2,
                EscrowMigrator,
                StakingRewardsNotifier,
                address,
                address,
                address
            )
        );

        // check staking rewards cannot be set to 0
        vm.expectRevert(IRewardEscrowV2.ZeroAddress.selector);
        rewardEscrowV2.setStakingRewards(address(0));

        // check staking rewards can only be set by owner
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        rewardEscrowV2.setStakingRewards(address(stakingRewardsV2));

        // check escrow migrator cannot be set to 0
        vm.expectRevert(IRewardEscrowV2.ZeroAddress.selector);
        rewardEscrowV2.setEscrowMigrator(address(0));

        // check escrow migrator can only be set by owner
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        rewardEscrowV2.setEscrowMigrator(address(escrowMigrator));

        // Setup StakingV2
        vm.expectEmit(true, true, true, true);
        emit StakingRewardsSet(address(stakingRewardsV2));
        vm.expectEmit(true, true, true, true);
        emit EscrowMigratorSet(address(escrowMigrator));
        (bool setupSuccess,) = address(migrate).delegatecall(
            abi.encodeWithSelector(
                migrate.setupSystem.selector,
                address(rewardEscrowV2),
                address(stakingRewardsV2),
                address(escrowMigrator),
                address(rewardsNotifier),
                address(treasury),
                false
            )
        );
        require(setupSuccess, "Migrate.setupSystem failed");
    }

    /*//////////////////////////////////////////////////////////////
                            Migration Helpers
    //////////////////////////////////////////////////////////////*/

    function switchToStakingV2() internal {
        // Update SupplySchedule to point to StakingV2
        (bool migrationSuccess,) = address(migrate).delegatecall(
            abi.encodeWithSelector(
                migrate.migrateSystem.selector,
                address(supplySchedule),
                address(rewardEscrowV1),
                address(rewardsNotifier),
                address(escrowMigrator),
                false
            )
        );
        require(migrationSuccess, "Migrate.migrateSystem failed");
    }
}
