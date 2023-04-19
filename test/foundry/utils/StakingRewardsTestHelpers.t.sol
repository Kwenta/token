// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {TestHelpers} from "../utils/TestHelpers.t.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
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
    RewardEscrowV2 public rewardEscrowV2;
    SupplySchedule public supplySchedule;
    StakingRewards public stakingRewardsV1;
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
        rewardEscrowV2 = new RewardEscrowV2(address(this), address(kwenta));
        supplySchedule = new SupplySchedule(address(this), treasury);
        kwenta.setSupplySchedule(address(supplySchedule));
        stakingRewardsV2 = new StakingRewardsV2(
            address(kwenta),
            address(rewardEscrowV2),
            address(supplySchedule)
        );
        supplySchedule.setStakingRewards(address(stakingRewardsV2));
        rewardEscrowV2.setStakingRewards(address(stakingRewardsV2));

        vm.prank(treasury);
        kwenta.transfer(address(stakingRewardsV2), INITIAL_SUPPLY / 4);
    }

    /*//////////////////////////////////////////////////////////////
                            V1 Helper Functions
    //////////////////////////////////////////////////////////////*/

    // UNIT HELPERS
    function fundAndApproveAccountV1(address account, uint256 amount) public {
        vm.prank(treasury);
        kwenta.transfer(account, amount);
        vm.prank(account);
        kwenta.approve(address(stakingRewardsV1), amount);
    }

    function fundAccountAndStakeV1(address account, uint256 amount) public {
        fundAndApproveAccountV1(account, amount);
        vm.prank(account);
        stakingRewardsV1.stake(amount);
    }
    
    function stakeFundsV1(address account, uint256 amount) public {
        vm.prank(account);
        kwenta.approve(address(stakingRewardsV1), amount);
        vm.prank(account);
        stakingRewardsV1.stake(amount);
    }

    function unstakeFundsV1(address account, uint256 amount) public {
        vm.prank(account);
        stakingRewardsV1.unstake(amount);
    }

    function getStakingRewardsV1(address account) public {
        vm.prank(account);
        stakingRewardsV1.getReward();
    }

    // INTEGRATION HELPERS
    function stakeAllUnstakedEscrowV1(address account) public {
        uint256 amount = getNonStakedEscrowAmountV1(account);
        vm.prank(account);
        rewardEscrowV1.stakeEscrow(amount);
    }

    function unstakeAllUnstakedEscrowV1(address account, uint256 amount) public {
        vm.prank(account);
        rewardEscrowV1.unstakeEscrow(amount);
    }

    function getNonStakedEscrowAmountV1(address account) public view returns (uint256) {
        return rewardEscrowV1.balanceOf(account) - stakingRewardsV1.escrowedBalanceOf(account);
    }

    /*//////////////////////////////////////////////////////////////
                            V2 Helper Functions
    //////////////////////////////////////////////////////////////*/

    // UNIT HELPERS
    function fundAndApproveAccountV2(address account, uint256 amount) public {
        vm.prank(treasury);
        kwenta.transfer(account, amount);
        vm.prank(account);
        kwenta.approve(address(stakingRewardsV2), amount);
    }

    function fundAccountAndStakeV2(address account, uint256 amount) public {
        fundAndApproveAccountV2(account, amount);
        vm.prank(account);
        stakingRewardsV2.stake(amount);
    }

    function stakeFundsV2(address account, uint256 amount) public {
        vm.prank(account);
        kwenta.approve(address(stakingRewardsV2), amount);
        vm.prank(account);
        stakingRewardsV2.stake(amount);
    }

    function unstakeFundsV2(address account, uint256 amount) public {
        vm.prank(account);
        stakingRewardsV2.unstake(amount);
    }

    // TODO: rename to make meaning more accurate and not conflict with V1
    function stakeEscrowedFundsV2(address account, uint256 amount) public {
        vm.prank(address(rewardEscrowV2));
        stakingRewardsV2.stakeEscrow(account, amount);
    }

    function unstakeEscrowedFundsV2(address account, uint256 amount) public {
        vm.prank(address(rewardEscrowV2));
        stakingRewardsV2.unstakeEscrow(account, amount);
    }
}
