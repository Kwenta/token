//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "forge-std/Test.sol";
import {Kwenta} from "../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../contracts/RewardEscrow.sol";
import {EscrowIssuer} from "../../contracts/EscrowIssuer.sol";

contract EscrowIssuerTest is Test {
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
    EscrowIssuer public escrowIssuer;

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
        escrowIssuer = new EscrowIssuer(
            "EscIss",
            "EIS",
            address(kwenta),
            address(rewardEscrow)
        );
    }

    function testIssueRedeemable() public {
        vm.startPrank(treasury);
        kwenta.approve(address(escrowIssuer), 10);
        escrowIssuer.issueRedeemable4YR(10);
        vm.stopPrank();

        assertEq(kwenta.balanceOf(address(escrowIssuer)), 10);
        assertEq(escrowIssuer.balanceOf(address(treasury)), 10);
    }

    function testIssueRedeemableFuzzing(uint96 amount) public {
        //only fuzz from 0-treasury balance
        vm.assume(amount < 313373 ether);

        vm.startPrank(treasury);
        kwenta.approve(address(escrowIssuer), amount);
        escrowIssuer.issueRedeemable4YR(amount);
        vm.stopPrank();

        assertEq(kwenta.balanceOf(address(escrowIssuer)), amount);
        assertEq(escrowIssuer.balanceOf(address(treasury)), amount);
    }

    function testRedeemEscrow() public {
        //setup
        vm.startPrank(treasury);
        kwenta.approve(address(escrowIssuer), 10);
        escrowIssuer.issueRedeemable4YR(10);
        escrowIssuer.transfer(user, 10);
        vm.stopPrank();

        //make sure vesting entry event is emitted
        vm.expectEmit(true, true, true, true);
        emit VestingEntryCreated(user, 10, 208 weeks, 1);
        vm.prank(user);
        escrowIssuer.redeemEscrow4YR(10);

        assertEq(kwenta.balanceOf(address(rewardEscrow)), 10);
        assertEq(kwenta.balanceOf(user), 0);
    }

    /**
        tests when someone tries to redeem tokens they don't have
     */
    function testFailRedeemEscrowNoTokens() public {
        vm.prank(user);
        escrowIssuer.redeemEscrow4YR(10);
    }
}
