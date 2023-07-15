// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

uint256 constant INITIAL_SUPPLY = 313_373 ether;
uint256 constant TEST_VALUE = 1 ether;

/*//////////////////////////////////////////////////////////////
                            FORK CONSTANTS
//////////////////////////////////////////////////////////////*/

uint256 constant OPTIMISM_BLOCK_NUMBER = 93_917_159;
uint256 constant OPTIMISM_BLOCK_NUMBER_JUST_AFTER_PAUSE = 106_849_995;
address constant OPTIMISM_STAKING_REWARDS_V1 = 0x6e56A5D49F775BA08041e28030bc7826b13489e0;
address constant OPTIMISM_REWARD_ESCROW_V1 = 0x1066A8eB3d90Af0Ad3F89839b974658577e75BE2;
address constant OPTIMISM_STAKING_REWARDS_V2 = 0xe5bB889B1f0B6B4B7384Bd19cbb37adBDDa941a6;
address constant OPTIMISM_REWARD_ESCROW_V2 = 0xd5fE5beAa04270B32f81Bf161768c44DF9880D11;
address constant OPTIMISM_KWENTA_TOKEN = 0x920Cf626a271321C151D027030D5d08aF699456b;
address constant OPTIMISM_SUPPLY_SCHEDULE = 0x3e8b82326Ff5f2f10da8CEa117bD44343ccb9c26;
address constant OPTIMISM_KWENTA_OWNER = 0xF510a2Ff7e9DD7e18629137adA4eb56B9c13E885;
address constant OPTIMISM_PDAO = 0xe826d43961a87fBE71C91d9B73F7ef9b16721C07;
address constant OPTIMISM_TREASURY_DAO = 0x82d2242257115351899894eF384f779b5ba8c695;
address constant OPTIMISM_RANDOM_STAKING_USER = 0x049569adb8a1e8A9349E9F1111C7b7993A4612eB;

/*//////////////////////////////////////////////////////////////
                        GOERLI ADDRESSES
//////////////////////////////////////////////////////////////*/

address constant OPTIMISM_GOERLI_KWENTA_TOKEN = 0xDA0C33402Fc1e10d18c532F0Ed9c1A6c5C9e386C;
address constant OPTIMISM_GOERLI_STAKING_REWARDS_V1 = 0x1653A3A3c4cceE0538685F1600a30dF5E3EE830A;
address constant OPTIMISM_GOERLI_REWARD_ESCROW_V1 = 0xaFD87d1a62260bD5714C55a1BB4057bDc8dFA413;
address constant OPTIMISM_GOERLI_SUPPLY_SCHEDULE = 0x671423b2e8a99882FD14BbD07e90Ae8B64A0E63A;
address constant OPTIMISM_GOERLI_TREASURY_DAO = 0xC2ecD777d06FFDF8B3179286BEabF52B67E9d991;
// This actually the MultipleMerkleDistributor contract
address constant OPTIMISM_GOERLI_TRADING_REWARDS = 0x74c0A3bD10634759DC8B4CA7078C8Bf85bFE1271;

/*//////////////////////////////////////////////////////////////
                            ROLLBACK DATA
//////////////////////////////////////////////////////////////*/

uint256 constant MINTED_TO_STAKING_REWARDS_V2 = 4_290_530_229_572_642_102_152; // 4290 KWENTA
uint256 constant TOTAL_STAKED_ESCROW_V2 = 455_395_557_014_486_600; // 0.4553 KWENTA
