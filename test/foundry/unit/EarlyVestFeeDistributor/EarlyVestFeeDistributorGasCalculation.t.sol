// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {IEarlyVestFeeDistributor} from "../../../../contracts/interfaces/IEarlyVestFeeDistributor.sol";
import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {EarlyVestFeeDistributorInternals} from "../../utils/EarlyVestFeeDistributorInternals.sol";
import {EarlyVestFeeDistributor} from "../../../../contracts/EarlyVestFeeDistributor.sol";

/// @notice test how many weeks we can go without checkpointing
/// and how much gas will it cost
contract EarlyVestFeeDistributorGasCalculation is DefaultStakingV2Setup {
    function setUp() public override {
        /// @dev starts after a week so the startTime is != 0
        goForward(1 weeks + 1);
        super.setUp();
        vm.prank(treasury);
        kwenta.transfer(address(this), 100_000 ether);
    }

    function testGas() public {
        for (int i = 0; i < 52; i++) {
            vm.prank(address(treasury));
            kwenta.transfer(address(earlyVestFeeDistributor), 3);
            goForward(1 weeks);
        }

        earlyVestFeeDistributor.checkpointToken();
    }
}
