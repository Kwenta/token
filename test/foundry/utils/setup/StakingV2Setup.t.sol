// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Test.sol";
import {Migrate} from "../../../../scripts/Migrate.s.sol";
import {StakingV1Setup} from "../../utils/setup/StakingV1Setup.t.sol";
import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";
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
        uint8 earlyVestingFee
    );
    event TreasuryDAOSet(address treasuryDAO);
    event EarlyVestFeeDistributorSet(address earlyVestFeeDistributor);
    event StakingRewardsSet(address stakingRewards);
    event EarlyVestFeeSentToDAO(uint256 amount);
    event EarlyVestFeeSentToDistributor(uint256 amount);

    /*//////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    RewardEscrowV2 public rewardEscrowV2;
    StakingRewardsV2 public stakingRewardsV2;
    Migrate public migrate;

    address rewardEscrowV2Implementation;
    address stakingRewardsV2Implementation;

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
                address(supplySchedule),
                address(stakingRewardsV1),
                false
            )
        );
        require(deploymentSuccess, "Migrate.deploySystem failed");
        (
            rewardEscrowV2,
            stakingRewardsV2,
            rewardEscrowV2Implementation,
            stakingRewardsV2Implementation
        ) = abi.decode(deploymentData, (RewardEscrowV2, StakingRewardsV2, address, address));

        // check staking rewards cannot be set to 0
        vm.expectRevert(IRewardEscrowV2.ZeroAddress.selector);
        rewardEscrowV2.setStakingRewards(address(0));

        // check staking rewards can only be set by owner
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        rewardEscrowV2.setStakingRewards(address(stakingRewardsV2));

        // Setup StakingV2
        vm.expectEmit(true, true, true, true);
        emit StakingRewardsSet(address(stakingRewardsV2));
        (bool setupSuccess,) = address(migrate).delegatecall(
            abi.encodeWithSelector(
                migrate.setupSystem.selector,
                address(rewardEscrowV2),
                address(stakingRewardsV2),
                address(treasury),
                false
            )
        );
        require(setupSuccess, "Migrate.setupSystem failed");

        rewardEscrowV2.setEarlyVestFeeDistributor(mockEarlyVestFeeDistributor);
    }

    /*//////////////////////////////////////////////////////////////
                            Migration Helpers
    //////////////////////////////////////////////////////////////*/

    function switchToStakingV2() public {
        // Update SupplySchedule to point to StakingV2
        (bool migrationSuccess,) = address(migrate).delegatecall(
            abi.encodeWithSelector(
                migrate.migrateSystem.selector,
                address(supplySchedule),
                address(stakingRewardsV2),
                false
            )
        );
        require(migrationSuccess, "Migrate.migrateSystem failed");
    }
}
