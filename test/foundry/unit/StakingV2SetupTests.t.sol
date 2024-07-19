// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Test.sol";
import {StakingV1Setup} from "../utils/setup/StakingV1Setup.t.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {EscrowMigrator} from "../../../contracts/EscrowMigrator.sol";
import {IStakingRewardsV2} from "../../../contracts/interfaces/IStakingRewardsV2.sol";
import {IRewardEscrowV2} from "../../../contracts/interfaces/IRewardEscrowV2.sol";
import {IEscrowMigrator} from "../../../contracts/interfaces/IEscrowMigrator.sol";
import "../utils/Constants.t.sol";

// Upgradeability imports
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract StakingV2SetupTests is StakingV1Setup {
    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    address public rewardEscrowV2Implementation;
    address public stakingRewardsV2Implementation;
    address public escrowMigratorImplementation;

    function setUp() public virtual override {
        super.setUp();

        rewardEscrowV2Implementation =
            address(new RewardEscrowV2(address(kwenta), address(0x1)));
    }

    /*//////////////////////////////////////////////////////////////
                      ESCROW MIGRATOR SETUP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Can_Deploy_EscrowMigrator_Implementation() public {
        (address rewardEscrowV2, address stakingRewardsV2) =
            deployRewardEscrowV2AndStakingRewardsV2(address(this));

        new EscrowMigrator(address(kwenta), address(rewardEscrowV1), rewardEscrowV2, stakingRewardsV2);
    }

    function test_Cannot_Setup_EscrowMigrator_With_Kwenta_Zero_Address() public {
        (address rewardEscrowV2, address stakingRewardsV2) =
            deployRewardEscrowV2AndStakingRewardsV2(address(this));

        vm.expectRevert(IEscrowMigrator.ZeroAddress.selector);
        new EscrowMigrator(address(0), address(rewardEscrowV1), rewardEscrowV2, stakingRewardsV2);
    }

    function test_Cannot_Setup_EscrowMigrator_With_RewardEscrowV1_Zero_Address() public {
        (address rewardEscrowV2, address stakingRewardsV2) =
            deployRewardEscrowV2AndStakingRewardsV2(address(this));

        vm.expectRevert(IEscrowMigrator.ZeroAddress.selector);
        new EscrowMigrator(address(kwenta), address(0), rewardEscrowV2, stakingRewardsV2);
    }

    function test_Cannot_Setup_EscrowMigrator_With_RewardEscrowV2_Zero_Address() public {
        (, address stakingRewardsV2) = deployRewardEscrowV2AndStakingRewardsV2(address(this));

        vm.expectRevert(IEscrowMigrator.ZeroAddress.selector);
        new EscrowMigrator(address(kwenta), address(rewardEscrowV1), address(0), stakingRewardsV2);
    }

    function test_Cannot_Setup_EscrowMigrator_With_StakingRewardsV2_Zero_Address() public {
        (address rewardEscrowV2,) = deployRewardEscrowV2AndStakingRewardsV2(address(this));

        vm.expectRevert(IEscrowMigrator.ZeroAddress.selector);
        new EscrowMigrator(address(kwenta), address(rewardEscrowV1), rewardEscrowV2, address(0));
    }

    function test_Cannot_Initialize_EscrowMigrator_Proxy_With_Owner_Zero_Address() public {
        (address rewardEscrowV2, address stakingRewardsV2) =
            deployRewardEscrowV2AndStakingRewardsV2(address(this));

        escrowMigratorImplementation = address(
            new EscrowMigrator(address(kwenta), address(rewardEscrowV1), rewardEscrowV2, stakingRewardsV2)
        );

        vm.expectRevert(IEscrowMigrator.ZeroAddress.selector);
        new ERC1967Proxy(
                escrowMigratorImplementation,
                abi.encodeWithSignature(
                    "initialize(address,address)",
                    address(0),
                    treasury
                )
            );
    }

    function test_Cannot_Initialize_EscrowMigrator_Proxy_With_Treasury_Zero_Address() public {
        (address rewardEscrowV2, address stakingRewardsV2) =
            deployRewardEscrowV2AndStakingRewardsV2(address(this));

        escrowMigratorImplementation = address(
            new EscrowMigrator(address(kwenta), address(rewardEscrowV1), rewardEscrowV2, stakingRewardsV2)
        );

        vm.expectRevert(IEscrowMigrator.ZeroAddress.selector);
        new ERC1967Proxy(
                escrowMigratorImplementation,
                abi.encodeWithSignature(
                    "initialize(address,address)",
                    address(0x1),
                    address(0)
                )
            );
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
        rewardEscrowV2Implementation = address(new RewardEscrowV2(address(0), address(0x1)));
    }

    function test_Cannot_Setup_RewardEscrowV2_With_RewardsNotifier_Zero_Address() public {
        vm.expectRevert(IRewardEscrowV2.ZeroAddress.selector);
        rewardEscrowV2Implementation = address(new RewardEscrowV2(address(0x1), address(0)));
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
                address(usdc),
                rewardEscrowV2,
                address(supplySchedule)
            )
        );
    }

    function test_Cannot_Setup_StakingRewardsV2_With_Usdc_Zero_Address() public {
        address rewardEscrowV2 = deployRewardEscrowV2(address(this));
        vm.expectRevert(IStakingRewardsV2.ZeroAddress.selector);
        stakingRewardsV2Implementation = address(
            new StakingRewardsV2(
                address(kwenta),
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
                address(usdc),
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
                address(usdc),
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
                address(usdc),
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

    function deployRewardEscrowV2AndStakingRewardsV2(address _owner)
        internal
        returns (address, address)
    {
        address rewardEscrowV2 = deployRewardEscrowV2(_owner);

        stakingRewardsV2Implementation = address(
            new StakingRewardsV2(
                address(kwenta),
                address(usdc),
                rewardEscrowV2,
                address(supplySchedule)
            )
        );

        address stakingRewardsV2 = deployStakingRewardsV2(_owner);

        return (rewardEscrowV2, stakingRewardsV2);
    }

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
