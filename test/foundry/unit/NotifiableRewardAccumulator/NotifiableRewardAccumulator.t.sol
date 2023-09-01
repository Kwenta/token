// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {Kwenta} from "../../../../contracts/Kwenta.sol";
import {RewardEscrowV2} from "../../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../../contracts/StakingRewardsV2.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {NotifiableRewardAccumulator} from "../../../../contracts/NotifiableRewardAccumulator.sol";

contract NotifiableRewardAccumulatorTest is DefaultStakingV2Setup {

    NotifiableRewardAccumulator public notifiableRewardAccumulator;

    function setUp() public override {
        super.setUp();
        vm.prank(treasury);
        kwenta.transfer(address(this), 100_000 ether);
    }

    function testExample() public {
        // do something
    }

}