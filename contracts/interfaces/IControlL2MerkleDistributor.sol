// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// allows messages from L1 -> L2
interface IControlL2MerkleDistributor {
    // allows an L1 account to call MerkleDistributor.claimToAddress() on L2
    function claimToAddress(uint256 index, address destAccount, uint256 amount, bytes32[] calldata merkleProof) external;
}
