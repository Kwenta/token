// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {TestHelpers} from "../utils/TestHelpers.t.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";

uint256 constant INITIAL_SUPPLY = 313373 ether;

contract StakingRewardsTestHelpers is TestHelpers {
    address public treasury;
    address public user1;
    address public user2;
    Kwenta public kwenta;
    RewardEscrow public rewardEscrow;
    SupplySchedule public supplySchedule;
    StakingRewardsV2 public stakingRewardsV2;

    function setUp() public {
        treasury = createUser();
        user1 = createUser();
        user2 = createUser();
        kwenta = new Kwenta(
            "Kwenta",
            "KWENTA",
            INITIAL_SUPPLY,
            address(this),
            treasury
        );
        rewardEscrow = new RewardEscrow(address(this), address(kwenta));
        supplySchedule = new SupplySchedule(address(this), treasury);
        kwenta.setSupplySchedule(address(supplySchedule));
        stakingRewardsV2 = new StakingRewardsV2(
            address(kwenta),
            address(rewardEscrow),
            address(supplySchedule)
        );
        supplySchedule.setStakingRewards(address(stakingRewardsV2));
        rewardEscrow.setStakingRewards(address(stakingRewardsV2));

        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV2), INITIAL_SUPPLY / 4);
    }

    function fundAndApproveAccount(address account, uint256 amount) public {
        vm.prank(treasury);
        kwenta.transfer(account, amount);
        vm.prank(account);
        kwenta.approve(address(stakingRewardsV2), amount);
    }
}
