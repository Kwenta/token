// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Migrate} from "../../../scripts/Migrate.s.sol";
import {TestHelpers} from "../utils/TestHelpers.t.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {StakingAccount} from "../../../contracts/StakingAccount.sol";
import {MultipleMerkleDistributor} from
    "../../../contracts/MultipleMerkleDistributor.sol";
import {IERC20} from "../../../contracts/interfaces/IERC20.sol";
import "../utils/Constants.t.sol";

contract StakingSetup is TestHelpers {
    /*//////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    address public treasury;
    address public user1;
    address public user2;
    address public user3;
    address public user4;
    address public user5;
    IERC20 public mockToken;
    Kwenta public kwenta;
    RewardEscrow public rewardEscrowV1;
    RewardEscrowV2 public rewardEscrowV2;
    SupplySchedule public supplySchedule;
    StakingRewards public stakingRewardsV1;
    StakingRewardsV2 public stakingRewardsV2;
    StakingAccount public stakingAccount;
    MultipleMerkleDistributor public tradingRewards;
    Migrate public migrate;

    /*//////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        // Setup StakingV1
        treasury = createUser();
        user1 = createUser();
        user2 = createUser();
        user3 = createUser();
        user4 = createUser();
        user5 = createUser();
        mockToken = new Kwenta(
            "Mock",
            "MOCK",
            INITIAL_SUPPLY,
            address(this),
            treasury
        );
        kwenta = new Kwenta(
            "Kwenta",
            "KWENTA",
            INITIAL_SUPPLY,
            address(this),
            treasury
        );
        rewardEscrowV1 = new RewardEscrow(address(this), address(kwenta));
        supplySchedule = new SupplySchedule(address(this), treasury);
        supplySchedule.setKwenta(kwenta);
        kwenta.setSupplySchedule(address(supplySchedule));
        stakingRewardsV1 = new StakingRewards(
            address(kwenta),
            address(rewardEscrowV1),
            address(supplySchedule)
        );
        tradingRewards =
            new MultipleMerkleDistributor(address(this), address(kwenta));
        supplySchedule.setStakingRewards(address(stakingRewardsV1));
        supplySchedule.setTradingRewards(address(tradingRewards));
        rewardEscrowV1.setStakingRewards(address(stakingRewardsV1));

        // Deploy StakingV2
        migrate = new Migrate();
        (bool deploymentSuccess, bytes memory deploymentData) = address(migrate)
            .delegatecall(
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
        (rewardEscrowV2, stakingRewardsV2, stakingAccount,,, ) =
            abi.decode(deploymentData, (RewardEscrowV2, StakingRewardsV2, StakingAccount, address, address, address));

        // Setup StakingV2
        (bool setupSuccess,) = address(migrate).delegatecall(
            abi.encodeWithSelector(
                migrate.setupSystem.selector,
                address(rewardEscrowV2),
                address(stakingRewardsV2),
                address(stakingAccount),
                address(treasury),
                false
            )
        );
        require(setupSuccess, "Migrate.setupSystem failed");
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
