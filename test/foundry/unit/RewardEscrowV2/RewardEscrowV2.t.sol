// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {DefaultStakingV2Setup} from "../../utils/setup/DefaultStakingV2Setup.t.sol";
import {IRewardEscrowV2} from "../../../../contracts/interfaces/IRewardEscrowV2.sol";
import {IStakingRewardsV2} from "../../../../contracts/interfaces/IStakingRewardsV2.sol";
import "../../utils/Constants.t.sol";

contract RewardEscrowV2Tests is DefaultStakingV2Setup {
    /*//////////////////////////////////////////////////////////////
                        Deploys Correctly
    //////////////////////////////////////////////////////////////*/

    function test_Should_Have_A_Kwenta_Token() public {
        assertEq(address(rewardEscrowV2.getKwentaAddress()), address(kwenta));
    }

    function test_Should_Set_Owner() public {
        assertEq(address(rewardEscrowV2.owner()), address(this));
    }

    function test_Should_Set_StakingRewards() public {
        assertEq(address(rewardEscrowV2.stakingRewards()), address(stakingRewardsV2));
    }

    function test_Should_Set_Treasury() public {
        assertEq(address(rewardEscrowV2.treasuryDAO()), address(treasury));
    }

    function test_Should_Not_Allow_Treasury_To_Be_Set_To_Zero_Address() public {
        vm.expectRevert(IRewardEscrowV2.ZeroAddress.selector);
        rewardEscrowV2.setTreasuryDAO(address(0));
    }

    function test_Setting_Treasury_DAO_Should_Emit_Event() public {
        vm.expectEmit(true, true, true, true);
        emit TreasuryDAOSet(address(this));
        rewardEscrowV2.setTreasuryDAO(address(this));
    }

    function test_Should_Not_Allow_Non_Owner_To_Set_Treasury_DAO() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        rewardEscrowV2.setTreasuryDAO(address(user1));
    }

    function test_Should_Not_Allow_StakingRewards_To_Be_Set_Twice() public {
        vm.expectRevert(IRewardEscrowV2.StakingRewardsAlreadySet.selector);
        rewardEscrowV2.setStakingRewards(address(stakingRewardsV1));
    }

    function test_Should_Set_nextEntryId_To_1() public {
        assertEq(rewardEscrowV2.nextEntryId(), 1);
    }

    /*//////////////////////////////////////////////////////////////
                            OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Only_Owner_Can_Set_Staking_TreasuryDAO() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        rewardEscrowV2.setTreasuryDAO(user1);
    }

    function test_Only_Owner_Can_Renounce_Ownership() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        stakingRewardsV2.renounceOwnership();
    }

    function test_Only_Owner_Can_Transfer_Ownership() public {
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        stakingRewardsV2.transferOwnership(user2);
    }

    function test_Renounce_Ownership() public {
        stakingRewardsV2.renounceOwnership();
        assertEq(stakingRewardsV2.owner(), address(0));
    }

    function test_Transfer_Ownership() public {
        // check ownership
        assertEq(rewardEscrowV2.owner(), address(this));

        // transfer ownership
        rewardEscrowV2.transferOwnership(user1);

        // accept ownership
        vm.prank(user1);
        rewardEscrowV2.acceptOwnership();

        // check ownership
        assertEq(rewardEscrowV2.owner(), address(user1));
        vm.expectRevert("Ownable: caller is not the owner");
        rewardEscrowV2.transferOwnership(address(this));

        // transfer ownership
        vm.prank(user1);
        rewardEscrowV2.transferOwnership(address(this));

        // accept ownership
        rewardEscrowV2.acceptOwnership();

        // check ownership
        assertEq(rewardEscrowV2.owner(), address(this));
    }

    /*//////////////////////////////////////////////////////////////
                        When No Escrow Entries
    //////////////////////////////////////////////////////////////*/

    function test_totalSupply_Should_Be_0() public {
        assertEq(rewardEscrowV2.totalSupply(), 0);
    }

    function test_balanceOf_Should_Be_0() public {
        assertEq(rewardEscrowV2.balanceOf(address(this)), 0);
    }

    function test_totalEscrowedAccountBalance_Should_Be_0() public {
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 0);
    }

    function test_totalVestedAccountBalance_Should_Be_0() public {
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);
    }

    function test_vest_Should_Do_Nothing_And_Not_Revert() public {
        entryIDs.push(0);
        rewardEscrowV2.vest(entryIDs);
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                Appending Vesting Schedules Error
    //////////////////////////////////////////////////////////////*/

    function test_appendVestingEntry_Should_Not_Create_A_Vesting_Entry_Insufficient_Kwenta()
        public
    {
        // assertion is violated
        vm.expectRevert();
        vm.prank(address(stakingRewardsV2));
        rewardEscrowV2.appendVestingEntry(address(this), 1 ether);
    }

    function test_appendVestingEntry_Should_Revert_If_Not_StakingRewards() public {
        vm.expectRevert(IRewardEscrowV2.OnlyStakingRewards.selector);
        rewardEscrowV2.appendVestingEntry(address(this), 1 ether);
    }

    function test_appendVestingEntry_Should_Revert_If_Beneficiary_Address_Is_Zero() public {
        vm.prank(treasury);
        kwenta.transfer(address(rewardEscrowV2), 1 ether);
        vm.prank(address(stakingRewardsV2));
        vm.expectRevert("ERC721: mint to the zero address");
        rewardEscrowV2.appendVestingEntry(address(0), 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                        Appending Vesting Schedules
    //////////////////////////////////////////////////////////////*/

    function test_Should_Return_Vesting_Entry() public {
        appendRewardEscrowEntryV2(address(this), TEST_VALUE);

        (uint256 endTime, uint256 escrowAmount, uint256 duration, uint256 earlyVestingFee) =
            rewardEscrowV2.getVestingEntry(1);

        assertEq(endTime, block.timestamp + 52 weeks);
        assertEq(escrowAmount, TEST_VALUE);
        assertEq(duration, 52 weeks);
        assertEq(earlyVestingFee, 90);
    }

    function test_Appends_New_Vesting_Entry_Event() public {
        vm.prank(treasury);
        kwenta.transfer(address(rewardEscrowV2), TEST_VALUE);
        vm.prank(address(stakingRewardsV2));
        vm.expectEmit(true, true, true, true);
        emit VestingEntryCreated(address(this), TEST_VALUE, 52 weeks, 1, 90);
        rewardEscrowV2.appendVestingEntry(address(this), TEST_VALUE);
    }

    function test_Should_Increment_nextEntryId() public {
        appendRewardEscrowEntryV2(address(this), TEST_VALUE);
        assertEq(rewardEscrowV2.nextEntryId(), 2);
    }

    function test_escrowedBalanceOf_Should_Be_Incremented() public {
        appendRewardEscrowEntryV2(address(this), TEST_VALUE);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), TEST_VALUE);
    }

    function test_totalVestedAccountBalance_Should_Be_Zero() public {
        appendRewardEscrowEntryV2(address(this), TEST_VALUE);
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);
    }

    function test_balanceOf_Should_Be_Incremented() public {
        appendRewardEscrowEntryV2(address(this), TEST_VALUE);
        assertEq(rewardEscrowV2.balanceOf(address(this)), 1);
    }

    function test_Correct_Amount_Claimable_After_6_Months() public {
        appendRewardEscrowEntryV2(address(this), 10 ether);

        vm.warp(block.timestamp + 26 weeks);

        (uint256 claimable,) = rewardEscrowV2.getVestingEntryClaimable(1);
        assertEq(claimable, 11 ether / 2);
    }

    function test_Correct_Amount_Claimable_After_6_Months_Fuzz(uint32 _amount) public {
        uint256 amount = _amount;
        vm.assume(amount > 0);

        appendRewardEscrowEntryV2(address(this), amount);

        vm.warp(block.timestamp + 26 weeks);

        (uint256 claimable, uint256 fee) = rewardEscrowV2.getVestingEntryClaimable(1);

        uint256 maxFee = amount * 90 / 100;
        uint256 earlyVestFee = maxFee * 26 weeks / 52 weeks;
        uint256 expectedClaimable = amount - earlyVestFee;

        assertEq(claimable, expectedClaimable);
        assertEq(fee, earlyVestFee);
    }

    function test_Correct_Amount_Claimable_After_1_Year() public {
        appendRewardEscrowEntryV2(address(this), TEST_VALUE);

        vm.warp(block.timestamp + 52 weeks);

        (uint256 claimable,) = rewardEscrowV2.getVestingEntryClaimable(1);
        assertEq(claimable, TEST_VALUE);
    }

    // TODO: create full fuzz test for different claim, amounts, waitTime and duration
    function test_Correct_Amount_Claimable_After_1_Year_Fuzz(uint32 _amount) public {
        uint256 amount = _amount;
        vm.assume(amount > 0);

        appendRewardEscrowEntryV2(address(this), amount);

        vm.warp(block.timestamp + 52 weeks);

        (uint256 claimable,) = rewardEscrowV2.getVestingEntryClaimable(1);
        assertEq(claimable, amount);
    }

    /*//////////////////////////////////////////////////////////////
                    Creating Vesting Schedules Errors
    //////////////////////////////////////////////////////////////*/

    function test_createEscrowEntry_Should_Not_Append_Entries_With_0_Amount() public {
        vm.expectRevert(IRewardEscrowV2.ZeroAmount.selector);
        rewardEscrowV2.createEscrowEntry(address(this), 0, 52 weeks, 90);
    }

    function test_createEscrowEntry_Should_Not_Append_Entries_With_Short_Duration() public {
        uint256 duration = stakingRewardsV2.cooldownPeriod();

        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), TEST_VALUE);
        vm.prank(treasury);
        vm.expectRevert(IRewardEscrowV2.InvalidDuration.selector);
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, duration - 1, 90);
    }

    function test_createEscrowEntry_Should_Not_Append_Entries_With_Bad_Duration_Fuzz(
        uint40 duration
    ) public {
        uint256 cooldownPeriod = stakingRewardsV2.cooldownPeriod();

        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), TEST_VALUE);
        if (duration < cooldownPeriod || duration > rewardEscrowV2.MAX_DURATION()) {
            vm.expectRevert(IRewardEscrowV2.InvalidDuration.selector);
        }
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, duration, 90);
    }

    function test_createEscrowEntry_Should_Not_Create_A_Vesting_Entry_Without_Allowance() public {
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, 52 weeks, 90);
    }

    function test_createEscrowEntry_Should_Revert_If_Duration_Is_0() public {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), TEST_VALUE);
        vm.expectRevert(IRewardEscrowV2.InvalidDuration.selector);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, 0, 90);
    }

    function test_createEscrowEntry_Should_Revert_If_Duration_Is_Greater_Than_Max() public {
        uint256 maxDuration = rewardEscrowV2.MAX_DURATION();
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), TEST_VALUE);
        vm.expectRevert(IRewardEscrowV2.InvalidDuration.selector);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, maxDuration + 1, 90);
    }

    function test_createEscrowEntry_Should_Revert_If_Beneficiary_Address_Is_Zero() public {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), TEST_VALUE);
        vm.expectRevert(IRewardEscrowV2.ZeroAddress.selector);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(address(0), TEST_VALUE, 52 weeks, 90);
    }

    function test_createEscrowEntry_Should_Revert_If_Early_Vesting_Fee_Is_Too_Low() public {
        uint256 earlyVestingFee = rewardEscrowV2.MINIMUM_EARLY_VESTING_FEE() - 1;
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), TEST_VALUE);
        vm.expectRevert(IRewardEscrowV2.EarlyVestingFeeTooLow.selector);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, 52 weeks, earlyVestingFee);
    }

    function test_createEscrowEntry_Should_Revert_If_Early_Vesting_Fee_Is_Too_Low_Fuzz(
        uint8 earlyVestingFee
    ) public {
        vm.assume(earlyVestingFee < rewardEscrowV2.MINIMUM_EARLY_VESTING_FEE());
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), TEST_VALUE);
        vm.expectRevert(IRewardEscrowV2.EarlyVestingFeeTooLow.selector);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, 52 weeks, earlyVestingFee);
    }

    function test_createEscrowEntry_Should_Revert_If_Early_Vesting_Fee_Is_Over_100() public {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), 1 ether);
        vm.expectRevert(IRewardEscrowV2.EarlyVestingFeeTooHigh.selector);
        vm.prank(treasury);
        rewardEscrowV2.createEscrowEntry(address(this), 1 ether, 52 weeks, 101);
    }

    /*//////////////////////////////////////////////////////////////
                        Creating Vesting Schedules
    //////////////////////////////////////////////////////////////*/

    function test_Creates_New_Vesting_Entry() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);

        (uint256 endTime, uint256 escrowAmount, uint256 duration, uint256 earlyVestingFee) =
            rewardEscrowV2.getVestingEntry(1);

        assertEq(endTime, block.timestamp + 52 weeks);
        assertEq(escrowAmount, TEST_VALUE);
        assertEq(duration, 52 weeks);
        assertEq(earlyVestingFee, 90);
    }

    function test_Creates_New_Vesting_Entry_Event() public {
        vm.prank(treasury);
        kwenta.approve(address(rewardEscrowV2), TEST_VALUE);
        vm.prank(treasury);
        vm.expectEmit(true, true, true, true);
        emit VestingEntryCreated(address(this), TEST_VALUE, 70 weeks, 1, 75);
        rewardEscrowV2.createEscrowEntry(address(this), TEST_VALUE, 70 weeks, 75);
    }

    function test_Increments_The_Next_Entry_ID() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        assertEq(rewardEscrowV2.nextEntryId(), 2);
    }

    function test_Increments_totalEscrowedBalance() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), TEST_VALUE);
    }

    function test_Increments_escrowedBalanceOf() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        assertEq(rewardEscrowV2.escrowedBalanceOf(address(this)), TEST_VALUE);
    }

    function test_totalVestedAccountBalance_Remains_0() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);
    }

    function test_balanceOf_Is_Incremented() public {
        createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        assertEq(rewardEscrowV2.balanceOf(address(this)), 1);
    }

    /*//////////////////////////////////////////////////////////////
                        Read Vesting Schedules
    //////////////////////////////////////////////////////////////*/

    function test_getVestingSchedules_InvalidIndex() public {
        createRewardEscrowEntryV2(user1, 200 ether, 52 weeks);
        createRewardEscrowEntryV2(user1, 200 ether, 52 weeks);
        createRewardEscrowEntryV2(user1, 200 ether, 52 weeks);
        createRewardEscrowEntryV2(user1, 200 ether, 52 weeks);
        createRewardEscrowEntryV2(user1, 200 ether, 52 weeks);

        IRewardEscrowV2.VestingEntryWithID[] memory entries =
            rewardEscrowV2.getVestingSchedules(user1, 6, 10);

        assertEq(entries.length, 0);
    }

    function test_getVestingSchedules() public {
        uint256 startTime = block.timestamp;

        createRewardEscrowEntryV2(user1, 200 ether, 52 weeks);
        vm.warp(block.timestamp + 1 weeks);
        createRewardEscrowEntryV2(user1, 300 ether, 52 weeks);
        vm.warp(block.timestamp + 1 weeks);
        createRewardEscrowEntryV2(user1, 500 ether, 52 weeks);

        IRewardEscrowV2.VestingEntryWithID[] memory entries =
            rewardEscrowV2.getVestingSchedules(user1, 0, 3);

        assertEq(entries.length, 3);

        // Check entry 1
        assertEq(entries[0].entryID, 1);
        assertEq(entries[0].endTime, startTime + 52 weeks);
        assertEq(entries[0].escrowAmount, 200 ether);

        // Check entry 2
        assertEq(entries[1].entryID, 2);
        assertEq(entries[1].endTime, startTime + 52 weeks + 1 weeks);
        assertEq(entries[1].escrowAmount, 300 ether);

        // Check entry 3
        assertEq(entries[2].entryID, 3);
        assertEq(entries[2].endTime, startTime + 52 weeks + 2 weeks);
        assertEq(entries[2].escrowAmount, 500 ether);
    }

    function test_getVestingSchedules_0_Page_Size() public {
        create3Entries(user1);

        IRewardEscrowV2.VestingEntryWithID[] memory entries =
            rewardEscrowV2.getVestingSchedules(user1, 0, 0);

        assertEq(entries.length, 0);
    }

    function test_getAccountVestingEntryIDs() public {
        create3Entries(address(this));

        uint256[] memory entries = rewardEscrowV2.getAccountVestingEntryIDs(address(this), 0, 3);

        assertEq(entries.length, 3);

        assertEq(entries[0], 1);
        assertEq(entries[1], 2);
        assertEq(entries[2], 3);
    }

    function test_getVestingQuantity() public {
        createRewardEscrowEntryV2(user1, 200 ether, 52 weeks);
        createRewardEscrowEntryV2(user1, 200 ether, 52 weeks);
        vm.warp(block.timestamp + 26 weeks);

        uint256[] memory entries = rewardEscrowV2.getAccountVestingEntryIDs(user1, 0, 2);

        (uint256 total, uint256 totalFee) = rewardEscrowV2.getVestingQuantity(entries);

        // 55% should be claimable
        assertEq(total, 220 ether);
        // 45% should be the fee
        assertEq(totalFee, 180 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                Vesting
    //////////////////////////////////////////////////////////////*/

    function test_Should_Vest_0_If_EntryID_Does_Not_Exist() public {
        appendRewardEscrowEntryV2(address(this), 1000 ether);
        vm.warp(block.timestamp + 26 weeks);

        entryIDs.push(200);
        rewardEscrowV2.vest(entryIDs);

        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);
        assertEq(kwenta.balanceOf(address(this)), 0);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 1000 ether);
    }

    function test_vest_Should_Properly_Distribute_Escrow_With_Distributor() public {
        appendRewardEscrowEntryV2(address(this), 1000 ether);
        vm.warp(block.timestamp + 26 weeks);

        // check initial values
        (uint256 claimable, uint256 fee) = rewardEscrowV2.getVestingEntryClaimable(1);
        assertEq(claimable, 550 ether);
        assertEq(fee, 450 ether);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 1000 ether);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 1000 ether);
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);

        uint256 treasuryBalanceBefore = kwenta.balanceOf(treasury);

        entryIDs.push(1);
        rewardEscrowV2.vest(entryIDs);

        uint256 treasuryBalanceAfter = kwenta.balanceOf(treasury);
        uint256 treasuryReceived = treasuryBalanceAfter - treasuryBalanceBefore;

        // 22.5% should go to the treasury
        assertEq(treasuryReceived, 225 ether);

        // 22.5% should go to RewardsNotifier
        assertEq(kwenta.balanceOf(address(rewardsNotifier)), 225 ether);

        // 55% should go to the staker
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 550 ether);
        assertEq(kwenta.balanceOf(address(this)), 550 ether);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 0);

        // Nothing should be left in reward escrow
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 0);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 0);
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 0);

        // check entry has been burned
        assertEq(rewardEscrowV2.balanceOf(address(this)), 0);
        vm.expectRevert("ERC721: invalid token ID");
        assertEq(rewardEscrowV2.ownerOf(1), address(0));

        // old vesting entry data still exists, except escrow amount reduced to 0
        (uint256 endTime, uint256 escrowAmount, uint256 duration, uint256 earlyVestingFee) =
            rewardEscrowV2.getVestingEntry(1);
        assertEq(escrowAmount, 0);
        assertEq(endTime, block.timestamp + 26 weeks);
        assertEq(duration, 52 weeks);
        assertEq(earlyVestingFee, 90);
    }

    function test_vest_Should_Properly_Emit_Event_With_Distributor() public {
        appendRewardEscrowEntryV2(address(this), 1000 ether);
        vm.warp(block.timestamp + 26 weeks);

        // check initial values
        (uint256 claimable, uint256 fee) = rewardEscrowV2.getVestingEntryClaimable(1);
        assertEq(claimable, 550 ether);
        assertEq(fee, 450 ether);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 1000 ether);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 1000 ether);
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);

        vm.expectEmit(true, true, true, true);
        emit EarlyVestFeeSent(225 ether, 225 ether);
        entryIDs.push(1);
        rewardEscrowV2.vest(entryIDs);
    }

    function test_Should_Revert_If_Kwenta_Transfer_Fails() public {
        appendRewardEscrowEntryV2(address(this), 1000 ether);

        // force kwenta out of reward escrow to cause a failure
        vm.prank(address(rewardEscrowV2));
        kwenta.transfer(user2, 700 ether);

        entryIDs.push(1);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        rewardEscrowV2.vest(entryIDs);
    }

    function test_vest_After_Duration_Has_Ended() public {
        appendRewardEscrowEntryV2(address(this), 1000 ether);
        vm.warp(block.timestamp + 52 weeks);

        entryIDs.push(1);
        rewardEscrowV2.vest(entryIDs);

        // check user has all their kwenta
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 1000 ether);
        assertEq(kwenta.balanceOf(address(this)), 1000 ether);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 0);

        // Nothing should be left in reward escrow
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 0);
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 0);
    }

    function test_vest_Event() public {
        appendRewardEscrowEntryV2(address(this), 1000 ether);
        vm.warp(block.timestamp + 52 weeks);
        entryIDs.push(1);

        vm.expectEmit(true, true, true, true);
        emit Vested(address(this), 1000 ether);
        rewardEscrowV2.vest(entryIDs);
    }

    /*//////////////////////////////////////////////////////////////
                        Vesting Multiple Entries
    //////////////////////////////////////////////////////////////*/

    function test_Should_Have_Three_Entries() public {
        create3Entries(address(this));
        assertEq(rewardEscrowV2.balanceOf(address(this)), 3);
    }

    function test_User_Cannot_Vest_Other_Users_Entries() public {
        create3Entries(address(this));
        vestAllEntries(user1);

        // kwenta not vested to owner of entries
        assertEq(kwenta.balanceOf(address(this)), 0);

        // kwenta not vested and sent to user attempting to steal
        assertEq(kwenta.balanceOf(user1), 0);

        // kwenta is all still locked in reward escrow
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 1000 ether);
    }

    function test_Should_Vest_All_Entries() public {
        createAndVest3Entries(address(this));

        assertEq(kwenta.balanceOf(address(this)), 1000 ether);
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 0);
    }

    function test_Should_Emit_Correct_Vested_Event() public {
        create3Entries(address(this));
        vm.expectEmit(true, true, true, true);
        emit Vested(address(this), 1000 ether);
        vestAllEntries(address(this));
    }

    function test_Should_Update_totalEscrowedAccountBalance() public {
        create3Entries(address(this));
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 1000 ether);
        vestAllEntries(address(this));
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 0);
    }

    function test_Should_Update_totalVestedAccountBalance() public {
        create3Entries(address(this));
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);
        vestAllEntries(address(this));
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 1000 ether);
    }

    function test_Should_Update_totalEscrowedBalance() public {
        create3Entries(address(this));
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 1000 ether);
        vestAllEntries(address(this));
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 0);
    }

    function test_Should_Ignore_Duplicate_Entries() public {
        create3Entries(address(this));
        uint256[] memory entries = rewardEscrowV2.getAccountVestingEntryIDs(address(this), 0, 100);
        for (uint256 i = 0; i < entries.length; i++) {
            entryIDs.push(entries[i]);
            entryIDs.push(entries[i]);
        }
        rewardEscrowV2.vest(entryIDs);

        // Check only 3 entries were vested
        assertEq(kwenta.balanceOf(address(this)), 1000 ether);
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 0);

        // Attempt to vest again
        rewardEscrowV2.vest(entryIDs);

        // Check only 3 entries were vested
        assertEq(kwenta.balanceOf(address(this)), 1000 ether);
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                Multiple Entries With Different Durations
    //////////////////////////////////////////////////////////////*/

    function test_3_Entries_Registered_With_User() public {
        create3EntriesWithDifferentDurations(address(this));
        assertEq(rewardEscrowV2.balanceOf(address(this)), 3);
    }

    function test_User_Cannot_Vest_Other_Users_Differing_Entries() public {
        create3EntriesWithDifferentDurations(address(this));
        vestAllEntries(user1);

        // kwenta not vested to owner of entries
        assertEq(kwenta.balanceOf(address(this)), 0);

        // kwenta not vested and sent to user attempting to steal
        assertEq(kwenta.balanceOf(user1), 0);

        // kwenta is all still locked in reward escrow
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 1000 ether);
    }

    function test_vest_First_Two_Entries() public {
        create3EntriesWithDifferentDurationsAndVestFirstTwo(address(this));

        // user has entry1 + entry2 amount
        assertEq(kwenta.balanceOf(address(this)), 500 ether);

        // reward escrow has entry3 amount
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 500 ether);
    }

    function test_vest_Should_Emit_Correct_Event_For_Two_Entries() public {
        create3EntriesWithDifferentDurations(address(this));
        vm.expectEmit(true, true, true, true);
        emit Vested(address(this), 500 ether);
        vestXEntries(address(this), 2);
    }

    function test_vest_Two_Entries_Should_Update_totalEscrowedAccountBalance() public {
        create3EntriesWithDifferentDurations(address(this));
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 1000 ether);
        vestXEntries(address(this), 2);
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 500 ether);
    }

    function test_vest_Two_Entries_Should_Update_totalVestedAccountBalance() public {
        create3EntriesWithDifferentDurations(address(this));
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);
        vestXEntries(address(this), 2);
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 500 ether);
    }

    function test_vest_Two_Entries_Should_Update_totalEscrowedBalance() public {
        create3EntriesWithDifferentDurations(address(this));
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 1000 ether);
        vestXEntries(address(this), 2);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 500 ether);
    }

    function test_vest_Two_Entries_Should_Ignore_Duplicate_Entries() public {
        create3EntriesWithDifferentDurations(address(this));
        uint256[] memory entries = rewardEscrowV2.getAccountVestingEntryIDs(address(this), 0, 100);
        for (uint256 i = 0; i < 2; i++) {
            entryIDs.push(entries[i]);
            entryIDs.push(entries[i]);
        }
        rewardEscrowV2.vest(entryIDs);

        // Check only 2 entries were vested
        assertEq(kwenta.balanceOf(address(this)), 500 ether);
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 500 ether);

        // Attempt to vest again
        rewardEscrowV2.vest(entryIDs);

        // Check only 2 entries were vested
        assertEq(kwenta.balanceOf(address(this)), 500 ether);
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 500 ether);
    }

    /*//////////////////////////////////////////////////////////////
                Vesting Fully and Partially Vested Entries
    //////////////////////////////////////////////////////////////*/

    function test_Entries_1_And_2_Fully_Vested_And_3_Partially_Vested() public {
        create3EntriesWithDifferentDurationsAndVestAll(address(this));

        // check entry1 + entry2 + some of entry3 vested
        assertGt(kwenta.balanceOf(address(this)), 500 ether);

        // check reward escrow is empty
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 0);
    }

    function test_vest_Should_Emit_Correct_Event_For_Three_Entries() public {
        create3EntriesWithDifferentDurations(address(this));
        vm.expectEmit(true, true, true, true);
        emit Vested(address(this), 775 ether);
        vestAllEntries(address(this));
    }

    function test_vest_Three_Entries_Should_Update_totalEscrowedAccountBalance() public {
        create3EntriesWithDifferentDurations(address(this));
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 1000 ether);
        vestAllEntries(address(this));
        assertEq(rewardEscrowV2.totalEscrowedAccountBalance(address(this)), 0 ether);
    }

    function test_vest_Three_Entries_Should_Update_totalVestedAccountBalance() public {
        create3EntriesWithDifferentDurations(address(this));
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 0);
        vestAllEntries(address(this));
        assertEq(rewardEscrowV2.totalVestedAccountBalance(address(this)), 775 ether);
    }

    function test_vest_Three_Entries_Should_Update_totalEscrowedBalance() public {
        create3EntriesWithDifferentDurations(address(this));
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 1000 ether);
        vestAllEntries(address(this));
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 0 ether);
    }

    function test_vest_Three_Entries_Should_Ignore_Duplicate_Entries() public {
        create3EntriesWithDifferentDurations(address(this));
        uint256[] memory entries = rewardEscrowV2.getAccountVestingEntryIDs(address(this), 0, 100);
        for (uint256 i = 0; i < entries.length; i++) {
            entryIDs.push(entries[i]);
            entryIDs.push(entries[i]);
        }
        rewardEscrowV2.vest(entryIDs);

        // Check only 2 entries were vested
        assertEq(kwenta.balanceOf(address(this)), 775 ether);
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 0 ether);

        // Attempt to vest again
        rewardEscrowV2.vest(entryIDs);

        // Check only 2 entries were vested
        assertEq(kwenta.balanceOf(address(this)), 775 ether);
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 0 ether);
    }

    /*//////////////////////////////////////////////////////////////
                    Stress Test Reading Vesting Schedule
    //////////////////////////////////////////////////////////////*/

    function test_Should_Return_Schedules() public {
        createXEntries(260);

        IRewardEscrowV2.VestingEntryWithID[] memory entries =
            rewardEscrowV2.getVestingSchedules(address(this), 0, 300);

        assertEq(entries.length, 260);
    }

    function test_Should_Return_List_Of_Entries() public {
        createXEntries(260);

        uint256[] memory entries = rewardEscrowV2.getAccountVestingEntryIDs(address(this), 0, 300);

        assertEq(entries.length, 260);
    }

    function test_Should_Return_Subset_Of_Entries() public {
        createXEntries(260);

        uint256[] memory entries = rewardEscrowV2.getAccountVestingEntryIDs(address(this), 130, 300);

        assertEq(entries.length, 130);
    }

    /*//////////////////////////////////////////////////////////////
                    Vesting With Staked Escrow
    //////////////////////////////////////////////////////////////*/

    function test_Should_Vest_Without_Unstaking_Escrow() public {
        createRewardEscrowEntryV2(address(this), 1 ether, 52 weeks);
        createRewardEscrowEntryV2(address(this), 1 ether, 52 weeks);

        // stake half the escrow
        stakingRewardsV2.stakeEscrow(1 ether);

        // vest first entry
        vm.warp(block.timestamp + 52 weeks);
        vestXEntries(address(this), 1);

        // check escrowed balance
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 1 ether);
        // nothing should have been unstaked
        assertEq(stakingRewardsV2.escrowedBalanceOf(address(this)), 1 ether);
    }

    function test_Should_Unstake_To_Vest_If_Needed() public {
        createRewardEscrowEntryV2(address(this), 1 ether, 52 weeks);

        // stake all the escrow
        stakingRewardsV2.stakeEscrow(1 ether);

        // move to end of vesting period
        vm.warp(block.timestamp + 52 weeks);

        // vest all entries
        vestAllEntries(address(this));

        // check escrowed balance
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 0 ether);
        // escrow should have been unstaked
        assertEq(stakingRewardsV2.escrowedBalanceOf(address(this)), 0 ether);
    }

    function test_Should_Unstake_Escrow_Partially_To_Vest() public {
        createRewardEscrowEntryV2(address(this), 100 ether, 52 weeks);

        // stake all the escrow
        stakingRewardsV2.stakeEscrow(100 ether);

        // move halfway to end of vesting period
        vm.warp(block.timestamp + 26 weeks);

        // vest all entries
        vestAllEntries(address(this));

        // check escrowed balance
        assertEq(rewardEscrowV2.escrowedBalanceOf(address(this)), 0 ether);
        // escrow should have been unstaked
        assertEq(stakingRewardsV2.escrowedBalanceOf(address(this)), 0 ether);
    }

    /*//////////////////////////////////////////////////////////////
                                Helpers
    //////////////////////////////////////////////////////////////*/

    function createXEntries(uint256 numEntries) public {
        for (uint256 i = 0; i < numEntries; i++) {
            createRewardEscrowEntryV2(address(this), TEST_VALUE, 52 weeks);
        }
    }

    function createAndVest3Entries(address user) public {
        create3Entries(user);
        vestAllEntries(user);
    }

    function vestAllEntries(address user) public {
        uint256[] memory entries = rewardEscrowV2.getAccountVestingEntryIDs(user, 0, 100);
        for (uint256 i = 0; i < entries.length; i++) {
            entryIDs.push(entries[i]);
        }
        vm.prank(user);
        rewardEscrowV2.vest(entryIDs);
    }

    function vestXEntries(address user, uint256 numToVest) public {
        uint256[] memory entries = rewardEscrowV2.getAccountVestingEntryIDs(user, 0, 100);
        for (uint256 i = 0; i < numToVest; i++) {
            entryIDs.push(entries[i]);
        }
        vm.prank(user);
        rewardEscrowV2.vest(entryIDs);
    }

    function create3Entries(address user) public {
        createRewardEscrowEntryV2(user, 200 ether, 52 weeks);
        vm.warp(block.timestamp + 1 weeks);
        createRewardEscrowEntryV2(user, 300 ether, 52 weeks);
        vm.warp(block.timestamp + 1 weeks);
        createRewardEscrowEntryV2(user, 500 ether, 52 weeks);
        vm.warp(block.timestamp + 52 weeks);
    }

    function create3EntriesWithDifferentDurationsAndVestFirstTwo(address user) public {
        create3EntriesWithDifferentDurations(user);
        vestXEntries(user, 2);
    }

    function create3EntriesWithDifferentDurationsAndVestAll(address user) public {
        create3EntriesWithDifferentDurations(user);
        vestAllEntries(user);
    }

    function create3EntriesWithDifferentDurations(address user) public {
        createRewardEscrowEntryV2(user, 200 ether, 52 weeks);
        vm.warp(block.timestamp + 1 weeks);
        createRewardEscrowEntryV2(user, 300 ether, 52 weeks);
        vm.warp(block.timestamp + 1 weeks);
        createRewardEscrowEntryV2(user, 500 ether, 52 weeks * 2);
        vm.warp(block.timestamp + 52 weeks);
    }
}
