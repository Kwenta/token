// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {TestHelpers} from "../utils/TestHelpers.t.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {IERC20} from "../../../contracts/interfaces/IERC20.sol";
import "../utils/Constants.t.sol";

contract StakingRewardsTestHelpers is TestHelpers {
    /*//////////////////////////////////////////////////////////////
                                Events
    //////////////////////////////////////////////////////////////*/

    event RewardsDurationUpdated(uint256 newDuration);
    event UnstakingCooldownPeriodUpdated(uint256 unstakingCooldownPeriod);

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
    SupplySchedule public supplySchedule;
    StakingRewardsV2 public stakingRewardsV2;

    /*//////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    function setUp() public virtual {
        treasury = createUser();
        user1 = createUser();
        user2 = createUser();
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
        kwenta.setSupplySchedule(address(supplySchedule));
        stakingRewardsV2 = new StakingRewardsV2(
            address(kwenta),
            address(rewardEscrowV1),
            address(supplySchedule)
        );
        supplySchedule.setStakingRewards(address(stakingRewardsV2));
        rewardEscrowV1.setStakingRewards(address(stakingRewardsV2));

        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV2), INITIAL_SUPPLY / 4);
    }

    /*//////////////////////////////////////////////////////////////
                            Helper Functions
    //////////////////////////////////////////////////////////////*/

    function fundAndApproveAccountV2(address account, uint256 amount) public {
        vm.prank(treasury);
        kwenta.transfer(account, amount);
        vm.prank(account);
        kwenta.approve(address(stakingRewardsV2), amount);
    }

    function stakeFundsV2(address account, uint256 amount) public {
        fundAndApproveAccountV2(account, amount);
        vm.prank(account);
        stakingRewardsV2.stake(amount);
    }

    function stakeEscrowedFundsV2(address account, uint256 amount) public {
        vm.prank(address(rewardEscrowV1));
        stakingRewardsV2.stakeEscrow(account, amount);
    }

    function unstakeEscrowedFundsV2(address account, uint256 amount) public {
        vm.prank(address(rewardEscrowV1));
        stakingRewardsV2.unstakeEscrow(account, amount);
    }
}
