// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Test.sol";
import {TestHelpers} from "../../utils/helpers/TestHelpers.t.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../../contracts/RewardEscrow.sol";
import {SupplySchedule} from "../../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../../contracts/StakingRewards.sol";
import {MultipleMerkleDistributor} from "../../../../contracts/MultipleMerkleDistributor.sol";
import "../../utils/Constants.t.sol";

contract StakingV1Setup is TestHelpers {
    /*//////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    address public mockEarlyVestFeeDistributor;
    address internal owner;
    address public treasury;
    address public user1;
    address public user2;
    address public user3;
    address public user4;
    address public user5;

    Kwenta internal kwenta;
    RewardEscrow internal rewardEscrowV1;
    SupplySchedule internal supplySchedule;
    StakingRewards internal stakingRewardsV1;
    MultipleMerkleDistributor internal tradingRewards;

    uint256[] internal entryIDs;

    /*//////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        // Setup StakingV1
        mockEarlyVestFeeDistributor = createUser();
        treasury = createUser();
        owner = address(this);
        user1 = createUser();
        user2 = createUser();
        user3 = createUser();
        user4 = createUser();
        user5 = createUser();
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
        tradingRewards = new MultipleMerkleDistributor(address(this), address(kwenta));
        supplySchedule.setStakingRewards(address(stakingRewardsV1));
        supplySchedule.setTradingRewards(address(tradingRewards));
        rewardEscrowV1.setStakingRewards(address(stakingRewardsV1));
    }
}
