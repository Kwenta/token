// SPDX-License-Identifier: MIT
pragma solidity ^0.5.16;

import "synthetix/contracts/StakingRewards.sol";

/// @notice For liquidity rewards mentioned in https://kips.kwenta.io/kips/kip-26/
/// @dev This contract only exists so that hardhat compiles synthetix/contracts/StakingRewards.sol
/// @dev v5 does not support the "abstract" keyword, but this contract is ABSTRACT
/* abstract */ contract LPRewards is StakingRewards {}