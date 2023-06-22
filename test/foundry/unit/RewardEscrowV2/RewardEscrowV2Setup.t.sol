// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {console} from "forge-std/Test.sol";
import {Migrate} from "../../../../scripts/Migrate.s.sol";
import {TestHelpers} from "../../utils/helpers/TestHelpers.t.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../../contracts/RewardEscrow.sol";
import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";
import {SupplySchedule} from "../../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../../contracts/StakingRewards.sol";
import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";
import {MultipleMerkleDistributor} from "../../../../contracts/MultipleMerkleDistributor.sol";
import {IRewardEscrowV2} from "../../../../contracts/interfaces/IRewardEscrowV2.sol";
import {IERC20} from "../../../../contracts/interfaces/IERC20.sol";
import "../../utils/Constants.t.sol";

// Upgradeability imports
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract RewardEscrowV2SetupTests is TestHelpers {
    /*//////////////////////////////////////////////////////////////
                                Setup
    //////////////////////////////////////////////////////////////*/

    function test_Cannot_Setup_With_Owner_Zero_Address() public {
        address treasury = createUser();
        Kwenta kwenta = new Kwenta(
                "Kwenta",
                "KWENTA",
                INITIAL_SUPPLY,
                address(this),
                treasury
            );

        // Deploy RewardEscrowV2
        address rewardEscrowV2Implementation = address(new RewardEscrowV2());
        vm.expectRevert("Ownable: new owner is the zero address");
        new ERC1967Proxy(
                rewardEscrowV2Implementation,
                abi.encodeWithSignature(
                "initialize(address,address)",
                address(0),
                address(kwenta)
                )
                );
    }

    function test_Cannot_Setup_With_Kwenta_Zero_Address() public {
        // Deploy RewardEscrowV2
        address rewardEscrowV2Implementation = address(new RewardEscrowV2());
        vm.expectRevert(IRewardEscrowV2.ZeroAddress.selector);
        new ERC1967Proxy(
                rewardEscrowV2Implementation,
                abi.encodeWithSignature(
                "initialize(address,address)",
                address(this),
                address(0)
                )
                );
    }
}
