// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Test.sol";
import {StakingV1Setup} from "../utils/setup/StakingV1Setup.t.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {IStakingRewardsV2} from "../../../contracts/interfaces/IStakingRewardsV2.sol";
import {IRewardEscrowV2} from "../../../contracts/interfaces/IRewardEscrowV2.sol";
import "../utils/Constants.t.sol";

// Upgradeability imports
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StakingV2SetupTests is StakingV1Setup {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    address public rewardEscrowV2Implementation;
    address public stakingRewardsV2Implementation;

    function setUp() public virtual override {
        super.setUp();

        rewardEscrowV2Implementation = address(new RewardEscrowV2(address(kwenta)));
    }

    /*//////////////////////////////////////////////////////////////
                       REWARDESCROWV2 SETUP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Setup_RewardEscrowV2_With_Owner_Zero_Address() public {
        vm.expectRevert(IRewardEscrowV2.ZeroAddress.selector);
        deployRewardEscrowV2(address(0));
    }

    function test_Cannot_Setup_RewardEscrowV2_With_Kwenta_Zero_Address() public {
        vm.expectRevert(IRewardEscrowV2.ZeroAddress.selector);
        rewardEscrowV2Implementation = address(new RewardEscrowV2(address(0)));
    }

    /*//////////////////////////////////////////////////////////////
                      STAKINGREWARDSV2 SETUP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Setup_StakingRewardsV2_With_Kwenta_Zero_Address() public {
        address rewardEscrowV2 = deployRewardEscrowV2(address(this));
        vm.expectRevert(IStakingRewardsV2.ZeroAddress.selector);
        stakingRewardsV2Implementation = address(
            new StakingRewardsV2(
                address(0),
                rewardEscrowV2,
                address(supplySchedule)
            )
        );
    }

    function test_Cannot_Setup_StakingRewardsV2_With_RewardEscrowV2_Zero_Address() public {
        vm.expectRevert(IStakingRewardsV2.ZeroAddress.selector);
        stakingRewardsV2Implementation = address(
            new StakingRewardsV2(
                address(kwenta),
                address(0),
                address(supplySchedule)
            )
        );
    }

    function test_Cannot_Setup_StakingRewardsV2_With_SupplySchedule_Zero_Address() public {
        address rewardEscrowV2 = deployRewardEscrowV2(address(this));
        vm.expectRevert(IStakingRewardsV2.ZeroAddress.selector);
        stakingRewardsV2Implementation = address(
            new StakingRewardsV2(
                address(kwenta),
                rewardEscrowV2,
                address(0)
            )
        );
    }

    function test_Cannot_Setup_StakingRewardsV2_With_Owner_Zero_Address() public {
        address rewardEscrowV2 = deployRewardEscrowV2(address(this));
        stakingRewardsV2Implementation = address(
            new StakingRewardsV2(
                address(kwenta),
                rewardEscrowV2,
                address(supplySchedule)
            )
        );
        vm.expectRevert(IStakingRewardsV2.ZeroAddress.selector);
        deployStakingRewardsV2(address(0));
    }

    /*//////////////////////////////////////////////////////////////
                                HELPERS
    //////////////////////////////////////////////////////////////*/

    function deployRewardEscrowV2(address _owner) internal returns (address) {
        return address(
            new ERC1967Proxy(
                    rewardEscrowV2Implementation,
                    abi.encodeWithSignature(
                        "initialize(address)",
                        _owner
                    )
                )
        );
    }

    function deployStakingRewardsV2(address _owner) internal returns (address) {
        return address(
            new ERC1967Proxy(
                    stakingRewardsV2Implementation,
                    abi.encodeWithSignature(
                        "initialize(address)",
                        _owner
                    )
                )
        );
    }
}
