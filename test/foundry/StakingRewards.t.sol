// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {Kwenta} from "../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../contracts/RewardEscrow.sol";
import {SupplySchedule} from "../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../contracts/StakingRewards.sol";

contract StakingRewardsTest is Test {
    address public treasury;
    Kwenta public kwenta;
    RewardEscrow public rewardEscrow;
    SupplySchedule public supplySchedule;
    StakingRewards public stakingRewards;

    function setUp() public {
        treasury = address(this);
        kwenta = new Kwenta(
            "Kwenta",
            "KWENTA",
            313373 ether,
            address(this),
            treasury
        );
        rewardEscrow = new RewardEscrow(address(this), address(kwenta));
        supplySchedule = new SupplySchedule(address(this), treasury);
        stakingRewards = new StakingRewards(
            address(kwenta),
            address(rewardEscrow),
            address(supplySchedule)
        );
    }

    function testOwner() public {
        address owner = stakingRewards.owner();
        assertEq(owner, address(this));
    }
}
