// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.19;

import {console} from "forge-std/Test.sol";
import {StakingTestHelpers} from "../utils/helpers/StakingTestHelpers.t.sol";
import {Migrate} from "../../../scripts/Migrate.s.sol";
import {Kwenta} from "../../../contracts/Kwenta.sol";
import {RewardEscrow} from "../../../contracts/RewardEscrow.sol";
import {RewardEscrowV2} from "../../../contracts/RewardEscrowV2.sol";
import {StakingRewardsV2} from "../../../contracts/StakingRewardsV2.sol";
import {SupplySchedule} from "../../../contracts/SupplySchedule.sol";
import {StakingRewards} from "../../../contracts/StakingRewards.sol";
import {Rollback} from "../../../scripts/v2-migration/Rollback.s.sol";
import "../utils/Constants.t.sol";

contract StakingV2MigrationForkTests is StakingTestHelpers {
    /*//////////////////////////////////////////////////////////////
                                STATE
    //////////////////////////////////////////////////////////////*/

    address internal owner;
    address internal rewardEscrowV2RollbackImpl;
    address internal stakingRewardsV2RollbackImpl;
    Rollback internal rollback;

    /*//////////////////////////////////////////////////////////////
                                SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public override {
        vm.rollFork(OPTIMISM_BLOCK_NUMBER_JUST_BEFORE_ROLLBACK);

        // define main contracts
        kwenta = Kwenta(OPTIMISM_KWENTA_TOKEN);
        rewardEscrowV1 = RewardEscrow(OPTIMISM_REWARD_ESCROW_V1);
        supplySchedule = SupplySchedule(OPTIMISM_SUPPLY_SCHEDULE);
        stakingRewardsV1 = StakingRewards(OPTIMISM_STAKING_REWARDS_V1);

        // define main addresses
        owner = OPTIMISM_PDAO;
        treasury = OPTIMISM_TREASURY_DAO;
        user1 = OPTIMISM_RANDOM_STAKING_USER;
        user2 = createUser();

        rewardEscrowV2 = RewardEscrowV2(OPTIMISM_REWARD_ESCROW_V2);
        stakingRewardsV2 = StakingRewardsV2(OPTIMISM_STAKING_REWARDS_V2);

        rollback = new Rollback();
        (rewardEscrowV2RollbackImpl, stakingRewardsV2RollbackImpl) = rollback.deploySystem(
            address(kwenta),
            address(rewardEscrowV2),
            address(supplySchedule),
            address(stakingRewardsV1),
            false
        );
    }

    /*//////////////////////////////////////////////////////////////
                   CALCULATION OF AMOUNT TO WITHDRAW
    //////////////////////////////////////////////////////////////*/

    function howMuchWeShouldWithdraw() public view returns (uint256) {
        /// @dev the number for TOTAL_STAKED_ESCROW_V2 was calculated off-chain (this is the only way)
        /// @dev in order to know the exact amount of liquid kwenta staked in the contract we have to use this off-chain data
        /// @dev in the test file stakingV2.rollback.fork.t there is a test `test_Roll_Back`
        /// @dev this test iterates through all 81 staked users and unstakes their kwenta after recoverFundsForRollback is called
        /// @dev the test is doing using vm.rollFork on optimism mainnet to just after this contract was paused
        /// @dev this shows that there will still be enough KWENTA in the contract for all users to unstake after this function is called
        uint256 totalLiquidStaked = stakingRewardsV2.totalSupply() - TOTAL_STAKED_ESCROW_V2;
        uint256 balance = kwenta.balanceOf(address(stakingRewardsV2));
        uint256 kwentaThatCanBeClaimed = balance - totalLiquidStaked;
        return kwentaThatCanBeClaimed;
    }

    /*//////////////////////////////////////////////////////////////
                                TESTS
    //////////////////////////////////////////////////////////////*/

    function test_recoverFundsForRollback_Only_Owner() public {
        // upgrade staking v2 contract
        vm.prank(owner);
        stakingRewardsV2.upgradeTo(stakingRewardsV2RollbackImpl);

        // try to recover funds as non-owner
        uint256 amountWeShouldWithdraw = howMuchWeShouldWithdraw();
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        stakingRewardsV2.recoverFundsForRollback(user1, amountWeShouldWithdraw);

        // try to recover funds as owner
        vm.prank(owner);
        stakingRewardsV2.recoverFundsForRollback(owner, amountWeShouldWithdraw);
    }

    function test_Roll_Back() public {
        upgradeToRollbackContracts();

        uint256 balanceBefore = kwenta.balanceOf(owner);

        // recover funds
        uint256 amountWeShouldWithdraw = howMuchWeShouldWithdraw();
        console.log("can be transferred:", amountWeShouldWithdraw);
        vm.prank(owner);
        stakingRewardsV2.recoverFundsForRollback(owner, amountWeShouldWithdraw);

        uint256 balanceAfter = kwenta.balanceOf(owner);
        uint256 balanceRecovered = balanceAfter - balanceBefore;

        // allow ~1 ether difference as 0.7971 KWENTA was sent to staking rewards
        assertCloseTo(balanceRecovered, MINTED_TO_STAKING_REWARDS_V2, 1 ether);
        // make sure the recovered amount is less than the amount minted to staking rewards
        assertLt(balanceRecovered, MINTED_TO_STAKING_REWARDS_V2);

        uint256 amountUsersNeedToUnstake = stakingRewardsV2.totalSupply() - TOTAL_STAKED_ESCROW_V2;
        assertGe(kwenta.balanceOf(address(stakingRewardsV2)), amountUsersNeedToUnstake);

        /// all users unstake
        attemptToUnstakeOnBehalfOfAllStakedUsers();

        // all users unstake escrow
        attemptToVestOnBehalfOfAllEscrowedUsers();

        // check all funds safely removed
        assertEq(stakingRewardsV2.totalSupply(), 0);
        assertEq(rewardEscrowV2.totalEscrowedBalance(), 0);
        assertEq(kwenta.balanceOf(address(rewardEscrowV2)), 0);
        assertCloseTo(kwenta.balanceOf(address(stakingRewardsV2)), 0, 10);
    }

    function test_Redistrubte_Rewards_2_Weeks() public {
        uint256 SUPPLY_MINTED = 6_316_072_210_012_118_228_158;

        upgradeToRollbackContracts();
        uint256 amountWeShouldWithdraw = howMuchWeShouldWithdraw();
        console.log("to return to users:", amountWeShouldWithdraw);
        vm.prank(owner);
        stakingRewardsV2.recoverFundsForRollback(owner, amountWeShouldWithdraw);

        console.log("supplySchedule.treasuryDiversion()", supplySchedule.treasuryDiversion());
        (
            uint256 stakingRewardsNormallyWeek1,
            uint256 stakingRewardsWithExtraWeek1,
            uint256 supplyMintedWeek1
        ) = getNextWeeksDiff(SUPPLY_MINTED, 0);
        uint256 diffWeek1 = stakingRewardsWithExtraWeek1 - stakingRewardsNormallyWeek1;
        (
            uint256 stakingRewardsNormallyWeek2,
            uint256 stakingRewardsWithExtraWeek2,
            uint256 supplyMintedWeek2
        ) = getNextWeeksDiff(supplyMintedWeek1, 0);
        uint256 diffWeek2 = stakingRewardsWithExtraWeek2 - stakingRewardsNormallyWeek2;

        console.log("diffWeek1", diffWeek1);
        console.log("diffWeek2", diffWeek2);
        uint256 totalDiff = diffWeek1 + diffWeek2;
        assertLt(totalDiff, amountWeShouldWithdraw);
        assertCloseTo(totalDiff, amountWeShouldWithdraw, 1 ether);
        console.log("totalDiff", totalDiff);

        uint256 extraStolen = amountWeShouldWithdraw - totalDiff;
        console.log("extraStolen", extraStolen); // 0.2 KWENTA
    }

    function test_Redistrubte_Rewards_3_Weeks() public {
        uint256 SUPPLY_MINTED = 6_316_072_210_012_118_228_158;

        upgradeToRollbackContracts();
        uint256 amountWeShouldWithdraw = howMuchWeShouldWithdraw();
        console.log("to return to users:", amountWeShouldWithdraw);
        vm.prank(owner);
        stakingRewardsV2.recoverFundsForRollback(owner, amountWeShouldWithdraw);

        console.log("supplySchedule.treasuryDiversion()", supplySchedule.treasuryDiversion());
        (
            uint256 stakingRewardsNormallyWeek1,
            uint256 stakingRewardsWithExtraWeek1,
            uint256 supplyMintedWeek1
        ) = getNextWeeksDiff(SUPPLY_MINTED, 1140);
        uint256 diffWeek1 = stakingRewardsWithExtraWeek1 - stakingRewardsNormallyWeek1;
        (
            uint256 stakingRewardsNormallyWeek2,
            uint256 stakingRewardsWithExtraWeek2,
            uint256 supplyMintedWeek2
        ) = getNextWeeksDiff(supplyMintedWeek1, 1140);
        uint256 diffWeek2 = stakingRewardsWithExtraWeek2 - stakingRewardsNormallyWeek2;
        (
            uint256 stakingRewardsNormallyWeek3,
            uint256 stakingRewardsWithExtraWeek3,
            uint256 supplyMintedWeek3
        ) = getNextWeeksDiff(supplyMintedWeek2, 1140);
        uint256 diffWeek3 = stakingRewardsWithExtraWeek3 - stakingRewardsNormallyWeek3;
        // assertGt(diff, amountWeShouldWithdraw);
        console.log("diffWeek1", diffWeek1);
        console.log("diffWeek2", diffWeek2);
        console.log("diffWeek3", diffWeek3);
        uint256 totalDiff = diffWeek1 + diffWeek2 + diffWeek3;
        assertGt(totalDiff, amountWeShouldWithdraw);
        assertCloseTo(totalDiff, amountWeShouldWithdraw, 6 ether);
        console.log("totalDiff", totalDiff);

        uint256 extraGivenAway = totalDiff - amountWeShouldWithdraw;
        console.log("extraGivenAway", extraGivenAway); // 0.2 KWENTA
    }

    function getNextWeeksDiff(uint256 lastWeeksRewards, uint256 newTreasuryDiversion)
        internal
        view
        returns (
            uint256 stakingRewardsNormally,
            uint256 stakingRewardsWithExtra,
            uint256 supplyMinted
        )
    {
        uint256 amountToDistribute = getExpectedSupplyMintedNextWeek(lastWeeksRewards);
        uint256 amountToTreasuryReduced = amountToDistribute * newTreasuryDiversion / 10_000;
        uint256 amountToTreasury = amountToDistribute * supplySchedule.treasuryDiversion() / 10_000;
        uint256 amountToTradingRewards =
            amountToDistribute * supplySchedule.tradingRewardsDiversion() / 10_000;
        stakingRewardsWithExtra =
            amountToDistribute - amountToTreasuryReduced - amountToTradingRewards;
        stakingRewardsNormally = amountToDistribute - amountToTreasury - amountToTradingRewards;
        supplyMinted = amountToDistribute;
    }

    function getExpectedSupplyMintedNextWeek(uint256 mintedLastWeek)
        internal
        pure
        returns (uint256)
    {
        return mintedLastWeek * 98 / 100;
    }

    /*//////////////////////////////////////////////////////////////
                            UPGRADE HELPERS
    //////////////////////////////////////////////////////////////*/

    function upgradeToRollbackContracts() public {
        // check contract is paused
        assertEq(stakingRewardsV2.paused(), true);

        // check correct owner is set
        assertEq(owner, stakingRewardsV2.owner());
        assertEq(owner, rewardEscrowV2.owner());

        // upgrade staking v2 contract
        vm.prank(owner);
        stakingRewardsV2.upgradeTo(stakingRewardsV2RollbackImpl);
        // upgrade reward escrow v2 contract
        vm.prank(owner);
        rewardEscrowV2.upgradeTo(rewardEscrowV2RollbackImpl);
    }

    /*//////////////////////////////////////////////////////////////
                            UNSTAKE HELPERS
    //////////////////////////////////////////////////////////////*/

    function attemptToUnstakeOnBehalfOfAllStakedUsers() internal {
        address[] memory liquidV2Stakers = getAllLiquidV2Stakers();
        for (uint256 i = 0; i < liquidV2Stakers.length; i++) {
            address staker = liquidV2Stakers[i];
            uint256 liquidBalance = stakingRewardsV2.nonEscrowedBalanceOf(staker);
            assert(liquidBalance > 0);
            uint256 userKwentaBalanceBefore = kwenta.balanceOf(staker);
            unstakeFundsV2(staker, liquidBalance);
            uint256 userKwentaBalanceAfter = kwenta.balanceOf(staker);
            assertEq(userKwentaBalanceAfter, userKwentaBalanceBefore + liquidBalance);
        }
    }

    function getAllLiquidV2Stakers() internal pure returns (address[] memory) {
        address[] memory liquidV2Stakers = new address[](82);
        liquidV2Stakers[0] = 0xC2ecD777d06FFDF8B3179286BEabF52B67E9d991;
        liquidV2Stakers[1] = 0x066cD4Ca2f32E406fae981558A08c48A3107fe20;
        liquidV2Stakers[2] = 0x64Af258F8522Bb9dD2c2B648B9CBBCDbe986B0BF;
        liquidV2Stakers[3] = 0x2Efe51893ea74043a4feAe2900c1b8f2FcE39b11;
        liquidV2Stakers[4] = 0xa12EeC92d8C155C8ea9159Cb87da4e062BF9992d;
        liquidV2Stakers[5] = 0xBA19C073C28f203d9FE23EEfeFA01A6d2562360F;
        liquidV2Stakers[6] = 0x4fBE5303bCa958b8f1ee35b5443Aad9aD442e3D7;
        liquidV2Stakers[7] = 0xbF49B454818783D12Bf4f3375ff17C59015e66Cb;
        liquidV2Stakers[8] = 0xcFBa6D63EC822425775d3C509E60ff689C1Ae1e7;
        liquidV2Stakers[9] = 0xC2a16805C137FA13FE9c02a86d83Ec4cc2BcC897;
        liquidV2Stakers[10] = 0x2C678004AF4c1e217d9ED8Baabd4454406CeB63D;
        liquidV2Stakers[11] = 0x51e432dF264c3315Bb0D1aA70D265cDF0792c679;
        liquidV2Stakers[12] = 0x33F366165F87f5f9b09E49f96F547aD53792FfD7;
        liquidV2Stakers[13] = 0x9194eFdF03174a804f3552F4F7B7A4bB74BaDb7F;
        liquidV2Stakers[14] = 0x7246a35ffcae7fbbc1Cd4FC6F78d3eEb4CE58f0C;
        liquidV2Stakers[15] = 0x6B3b856e974c61D141521725a73a58b916FBA49a;
        liquidV2Stakers[16] = 0xFdbBfB0Fe2986672af97Eca0e797D76A0bbF35c9;
        liquidV2Stakers[17] = 0x05e09d942505764bca4475ABf8efdBc21D1c535B;
        liquidV2Stakers[18] = 0xC814d2ef6D893568c74cD969Eb6F72a62fc261f7;
        liquidV2Stakers[19] = 0xA110d783a5b6B0B2A2C867094364E8f9752D5B93;
        liquidV2Stakers[20] = 0x2f7b5b606C449F0D40340dF9e917d14Cf0f05B1F;
        liquidV2Stakers[21] = 0x579EC43e42F86d041ef810b85817db202192b288;
        liquidV2Stakers[22] = 0xDFFD8BBf8dcAF236C4e009Ff6013Bfc98407B6C0;
        liquidV2Stakers[23] = 0x453e692bEa81E32CAa6AE385CeCF8c9cb85d443e;
        liquidV2Stakers[24] = 0x4CE405C7A6db483bCb0537146c20697E8d20F63b;
        liquidV2Stakers[25] = 0x11b6A5fE2906F3354145613DB0d99CEB51f604C9;
        liquidV2Stakers[26] = 0xC290067ef915116E31cE171097d4697Da36c8C43;
        liquidV2Stakers[27] = 0x6C369D4F1817017b7BA3Bf501Df1cb57d8F60545;
        liquidV2Stakers[28] = 0xFee6be6B5cc8Cb4EE8189850A69973E774e7614e;
        liquidV2Stakers[29] = 0x3bf2d5d15aCAE95b6C0be2F0a884d3d329F8BCDD;
        liquidV2Stakers[30] = 0xDBB056eb9C451cFE75AD06C7925562A48b65A625;
        liquidV2Stakers[31] = 0xfD41DC8DF72d91312eC0F982172c637ba4Faf1A7;
        liquidV2Stakers[32] = 0x633F6Bb51B30Aed1fec4625774919eCA9F5aA55E;
        liquidV2Stakers[33] = 0xB997887bFb6DDcB188b5f3693A15b3111F2f791a;
        liquidV2Stakers[34] = 0xf2E8666155003C8df650df6e6E1866810E81a391;
        liquidV2Stakers[35] = 0x37dc6358788dA0f43FB80A0A5212d0eAc43214b2;
        liquidV2Stakers[36] = 0x3dD81863779991D88d7F186D41b8beA1a569553d;
        liquidV2Stakers[37] = 0x764f4909251F81976A0A2DCeBcE95333e4C27517;
        liquidV2Stakers[38] = 0x6DE6E901Bbefd26a9888798a25E4A49309D04CA9;
        liquidV2Stakers[39] = 0x2db6F5e838eD2BaD993E9FF2D3d7A5c1Cc35704C;
        liquidV2Stakers[40] = 0x1cf5b33225f76E3d9FA3e51bc6FaC750B5C7f136;
        liquidV2Stakers[41] = 0xDFaB977372A039e78839687b8c359465f0f17532;
        liquidV2Stakers[42] = 0xac9F5A0A1C0F6862F2485B2F1390d31bfC90f4AB;
        liquidV2Stakers[43] = 0xE51e79FEe438000417C4FB609B933887dc758e3a;
        liquidV2Stakers[44] = 0xBbfB6566AD064C233af6314Aeb1EEE4C26A5f921;
        liquidV2Stakers[45] = 0x4831bb25C9E8fC4894e91949aa48310F8E261972;
        liquidV2Stakers[46] = 0x4883F9C4A25c9790ecE1EbC0b74337F33A53B430;
        liquidV2Stakers[47] = 0xfB21f8a7A67C1846B1034d13aE118855AD1b8da0;
        liquidV2Stakers[48] = 0xeA4007a31D9a81C52C5A5106DFCa203000E4E885;
        liquidV2Stakers[49] = 0x891F1D4DD7d4B3Bf1Be6a3AFCB5bBAADbea6320D;
        liquidV2Stakers[50] = 0xbEC85812e620b56525681312B12eFCe711A58135;
        liquidV2Stakers[51] = 0xF16ABC4F0Ca583A8612B8967db4Cd60ac92Ad288;
        liquidV2Stakers[52] = 0x5Db201AE15f9702f0a0Ff9F00b8c1c18355373d0;
        liquidV2Stakers[53] = 0xc97E11fcFF2e2a370c6AF376ABCdaa0045E31391;
        liquidV2Stakers[54] = 0x4713672c2cde7DcED86f7562864b2E31c870D11b;
        liquidV2Stakers[55] = 0xea25a4bA89792E3D13Bc31d947acda616F6d6736;
        liquidV2Stakers[56] = 0xd58f5434C7317E052B70BB6BcBF50B8F3c2a5Efd;
        liquidV2Stakers[57] = 0x05F4f690F1450daaE8892f76a8653004773E545c;
        liquidV2Stakers[58] = 0xF60595B5Bb6fa8135C0Feef89543521FF38Ba83E;
        liquidV2Stakers[59] = 0x85447824d5dc10B9fb75928f8104890Eb54E7Ce1;
        liquidV2Stakers[60] = 0x6fE6a38405816BfCE41AAbfC7D090B1C8AB594c1;
        liquidV2Stakers[61] = 0xeE097Bd75c6299dC12Fd91e31EC10B797d572747;
        liquidV2Stakers[62] = 0x917b4B0E86fC7766695095dD1A5292B3BE8b2D14;
        liquidV2Stakers[63] = 0x2b26dA567C2A8c220daF91be8E37A429D33AEF0B;
        liquidV2Stakers[64] = 0xC83F75C7ee4E4F931Dc3C689d2E68D840765e62C;
        liquidV2Stakers[65] = 0xFe1a00487DD9EB84a7363a1c827a6f045fB121E4;
        liquidV2Stakers[66] = 0xFaCEc1c32AE56097866A6c1dDA1124f2C6844F40;
        liquidV2Stakers[67] = 0xe973B2294CC76F2C9dcF7324667B363Cc2d6dC58;
        liquidV2Stakers[68] = 0x16d1663A00d4d1a216E0baa84B0AbC69ba35C156;
        liquidV2Stakers[69] = 0x667d58D5e1EAe29b384665686C5AD082b013FF95;
        liquidV2Stakers[70] = 0x12478d1a60a910C9CbFFb90648766a2bDD5918f5;
        liquidV2Stakers[71] = 0x99343B21B33243cE44acfad0a5620B758Ef8817a;
        liquidV2Stakers[72] = 0xE91cBC483A8fDA6bc377Ad8b8c717f386A93d349;
        liquidV2Stakers[73] = 0x920b4b547ED03A68709b7f28c7D8811df88930d7;
        liquidV2Stakers[74] = 0xaA62CF7caaf0c7E50Deaa9d5D0b907472F00B258;
        liquidV2Stakers[75] = 0x58aE6a82b0E52607013b28bfB106358d6499Dea4;
        liquidV2Stakers[76] = 0x5aEF99391FE6fc336f78E9169ba13565953Da258;
        liquidV2Stakers[77] = 0x038cDcccC1077ac50335Cf18FeAA308a0e0546b7;
        liquidV2Stakers[78] = 0x2EF0782745B9890c2D1047cBd33bE98e22ec35a2;
        liquidV2Stakers[79] = 0xC97cfd2c3a3E61316E931B784BdE21e61Ce15b82;
        liquidV2Stakers[80] = 0xa65Ba816f1f01ef234b8480b81A2ED5B3544c61a;
        liquidV2Stakers[81] = 0x8cAaf4cB80Ba7cbBbB324066BD03eAE3Fc98f813;
        return liquidV2Stakers;
    }

    function attemptToVestOnBehalfOfAllEscrowedUsers() internal {
        address[] memory usersWithV2Escrow = getAllUsersWithV2Escrow();
        for (uint256 i = 0; i < usersWithV2Escrow.length; i++) {
            address escrowedUser = usersWithV2Escrow[i];
            uint256 escrowedBalance = rewardEscrowV2.escrowedBalanceOf(escrowedUser);
            assert(escrowedBalance > 0);
            uint256 numberOfVestingEntries = rewardEscrowV2.balanceOf(escrowedUser);
            uint256[] memory _entryIDs =
                rewardEscrowV2.getAccountVestingEntryIDs(escrowedUser, 0, numberOfVestingEntries);
            uint256 userKwentaBalanceBefore = kwenta.balanceOf(escrowedUser);
            (uint256 total, uint256 totalFee) = rewardEscrowV2.getVestingQuantity(_entryIDs);
            assertEq(totalFee, 0);
            assertEq(total, escrowedBalance);
            vm.prank(escrowedUser);
            rewardEscrowV2.vest(_entryIDs);
            uint256 userKwentaBalanceAfter = kwenta.balanceOf(escrowedUser);
            assertEq(userKwentaBalanceAfter, userKwentaBalanceBefore + escrowedBalance);
        }
    }

    function getAllUsersWithV2Escrow() internal pure returns (address[] memory) {
        address[] memory usersWithV2Escrow = new address[](38);
        usersWithV2Escrow[0] = 0x2Efe51893ea74043a4feAe2900c1b8f2FcE39b11;
        usersWithV2Escrow[1] = 0xB69e74324bc030F1B5409236EFA461496D439116;
        usersWithV2Escrow[2] = 0xC1C79C6378e5A72895C8eA15fc6Dd59fFddc8dee;
        usersWithV2Escrow[3] = 0x17335ACa967138083B04dC70cEF828C83f5B6160;
        usersWithV2Escrow[4] = 0x2f31e5e4e0EDfE3f42B910aC7cD5ab25dd130114;
        usersWithV2Escrow[5] = 0xC2a16805C137FA13FE9c02a86d83Ec4cc2BcC897;
        usersWithV2Escrow[6] = 0x8a30Fd92823D5ACF7C74d8c6fC54143934caD3d6;
        usersWithV2Escrow[7] = 0xA178c15dd95553da5b79c1BA0bDE1659Fa2e76c8;
        usersWithV2Escrow[8] = 0x976FdC5DfA145E3cbc690E9fef4a408642732952;
        usersWithV2Escrow[9] = 0x05e09d942505764bca4475ABf8efdBc21D1c535B;
        usersWithV2Escrow[10] = 0xC814d2ef6D893568c74cD969Eb6F72a62fc261f7;
        usersWithV2Escrow[11] = 0x579EC43e42F86d041ef810b85817db202192b288;
        usersWithV2Escrow[12] = 0x4CE405C7A6db483bCb0537146c20697E8d20F63b;
        usersWithV2Escrow[13] = 0x529656620D914443405A55ec42Ad0eAEaF0b4A2c;
        usersWithV2Escrow[14] = 0x1140321cCE279B4a2158571eb377669Def562Ac4;
        usersWithV2Escrow[15] = 0x89808C49F858b86E80B892506CF11606Fb25fCDC;
        usersWithV2Escrow[16] = 0xD120Cf3e0408DD794f856e8CA2A23E3396A9B687;
        usersWithV2Escrow[17] = 0x2db6F5e838eD2BaD993E9FF2D3d7A5c1Cc35704C;
        usersWithV2Escrow[18] = 0x6DE6E901Bbefd26a9888798a25E4A49309D04CA9;
        usersWithV2Escrow[19] = 0xb8b0CC3793BBbfdb997FeC45828F172e5423D3E2;
        usersWithV2Escrow[20] = 0xc97E11fcFF2e2a370c6AF376ABCdaa0045E31391;
        usersWithV2Escrow[21] = 0x11eBeE2bF244325B5559f0F583722d35659DDcE8;
        usersWithV2Escrow[22] = 0xd58f5434C7317E052B70BB6BcBF50B8F3c2a5Efd;
        usersWithV2Escrow[23] = 0xFee6be6B5cc8Cb4EE8189850A69973E774e7614e;
        usersWithV2Escrow[24] = 0x5C2C3764A4Ba0a4ea4B81532aa48e3A72AD0655B;
        usersWithV2Escrow[25] = 0xFe1a00487DD9EB84a7363a1c827a6f045fB121E4;
        usersWithV2Escrow[26] = 0x51b47cdC53A6A0df80711a3AdFD549B055141Fa5;
        usersWithV2Escrow[27] = 0xFaCEc1c32AE56097866A6c1dDA1124f2C6844F40;
        usersWithV2Escrow[28] = 0x667d58D5e1EAe29b384665686C5AD082b013FF95;
        usersWithV2Escrow[29] = 0xDBB056eb9C451cFE75AD06C7925562A48b65A625;
        usersWithV2Escrow[30] = 0xB74B4347DffdB17E70e0dd3EB192f498844F56F7;
        usersWithV2Escrow[31] = 0x99343B21B33243cE44acfad0a5620B758Ef8817a;
        usersWithV2Escrow[32] = 0xE91cBC483A8fDA6bc377Ad8b8c717f386A93d349;
        usersWithV2Escrow[33] = 0xa65Ba816f1f01ef234b8480b81A2ED5B3544c61a;
        usersWithV2Escrow[34] = 0xC83F75C7ee4E4F931Dc3C689d2E68D840765e62C;
        usersWithV2Escrow[35] = 0x71535AAe1B6C0c51Db317B54d5eEe72d1ab843c1;
        usersWithV2Escrow[36] = 0x630f36ebd807f042a2477D50492Da8Cc7d86926a;
        usersWithV2Escrow[37] = 0xbF49B454818783D12Bf4f3375ff17C59015e66Cb;
        return usersWithV2Escrow;
    }
}
