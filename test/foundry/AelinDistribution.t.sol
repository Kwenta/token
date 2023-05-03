//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Kwenta} from "../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../contracts/RewardEscrow.sol";
import {AelinDistribution} from "../../contracts/AelinDistribution.sol";

contract AelinDistributionTest is Test {

    address public treasury;
    Kwenta public kwenta;
    RewardEscrow public rewardEscrow;
    AelinDistribution public aelinDistribution;

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
        aelinDistribution = new AelinDistribution("aelin", "ALN", address(kwenta), address(rewardEscrow));

    }

    function testIssueRedeemable() public {

        vm.prank(treasury);
        aelinDistribution.issueRedeemable1YR(10);

    }

}