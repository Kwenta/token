//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Kwenta} from "../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../contracts/RewardEscrow.sol";
import {AelinDistribution} from "../../contracts/AelinDistribution.sol";

contract AelinDistributionTest is Test {
    event VestingEntryCreated(
        address indexed beneficiary,
        uint value,
        uint duration,
        uint entryID
    );
    address public treasury;
    address public user;
    Kwenta public kwenta;
    RewardEscrow public rewardEscrow;
    AelinDistribution public aelinDistribution;

    function setUp() public {
        treasury = address(this);
        user = payable(
            address(uint160(uint256(keccak256(abi.encodePacked("user")))))
        );
        kwenta = new Kwenta(
            "Kwenta",
            "KWENTA",
            313373 ether,
            address(this),
            treasury
        );
        rewardEscrow = new RewardEscrow(address(this), address(kwenta));
        aelinDistribution = new AelinDistribution(
            "aelin",
            "ALN",
            address(kwenta),
            address(rewardEscrow)
        );
    }

    function testIssueRedeemable() public {
        vm.startPrank(treasury);
        kwenta.approve(address(aelinDistribution), 10);
        aelinDistribution.issueRedeemable1YR(10);
        vm.stopPrank();

        assertEq(kwenta.balanceOf(address(aelinDistribution)), 10);
        assertEq(aelinDistribution.balanceOf(address(treasury)), 10);
    }

    function testIssueRedeemableFuzzing(uint96 amount) public {
        //only fuzz from 0-treasury balance
        vm.assume(amount < 313373 ether);

        vm.startPrank(treasury);
        kwenta.approve(address(aelinDistribution), amount);
        aelinDistribution.issueRedeemable1YR(amount);
        vm.stopPrank();

        assertEq(kwenta.balanceOf(address(aelinDistribution)), amount);
        assertEq(aelinDistribution.balanceOf(address(treasury)), amount);
    }

    function testRedeemEscrow() public {
        //setup
        vm.startPrank(treasury);
        kwenta.approve(address(aelinDistribution), 10);
        aelinDistribution.issueRedeemable1YR(10);
        aelinDistribution.transfer(user, 10);
        vm.stopPrank();

        //make sure vesting entry event is emitted
        vm.expectEmit(true, true, true, true);
        emit VestingEntryCreated(user, 10, 52 weeks, 1);
        vm.prank(user);
        aelinDistribution.redeemEscrow1YR(10);

        assertEq(kwenta.balanceOf(address(rewardEscrow)), 10);
        assertEq(kwenta.balanceOf(user), 0);
    }

    /**
        tests when someone tries to redeem tokens they don't have
     */
    function testFailRedeemEscrowNoTokens() public {
        vm.prank(user);
        aelinDistribution.redeemEscrow1YR(10);
    }
}
