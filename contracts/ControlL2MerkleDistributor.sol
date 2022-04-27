// SPDX-License-Identifier: Unlicense
// This contracts runs on L1, and controls a MerkleDistributor on L2
pragma solidity ^0.8.0;

import "./interfaces/IControlL2MerkleDistributor.sol";

import { ICrossDomainMessenger } from 
    "@eth-optimism/contracts/libraries/bridge/ICrossDomainMessenger.sol";
    
contract ControlL2MerkleDistributor is IControlL2MerkleDistributor {
    // communication between L1 and L2 is enabled by two special smart contracts called the "messengers"
    // and below is the address for the messenger on L1
    address immutable crossDomainMessengerAddr;

    // MerkleDistributor deployed on L2
    address immutable merkleDistributorL2Address;

    constructor(address _crossDomainMessengerAddr, address _merkleDistributorL2Address) {
        crossDomainMessengerAddr = _crossDomainMessengerAddr;
        merkleDistributorL2Address = _merkleDistributorL2Address;
    }

    /*
     * claim $KWENTA on L2 from an L1 address
     * @notice destAccount will be the address used to create new escrow entry
     * @param index: used for merkle tree verification
     * @param destAccount: address used for escrow entry
     * @param amount: $KWENTA amount to be escrowed
     * @param merkleProof: off-chain generated proof of merkle tree inclusion
     */ 
    function claimToAddress(uint256 index, address destAccount, uint256 amount, bytes32[] calldata merkleProof) external override {
        bytes memory message;
        message = abi.encodeWithSignature(
            "claimToAddress(uint256,address,uint256,bytes32[])",
            index, 
            destAccount, 
            amount, 
            merkleProof
        );

        ICrossDomainMessenger(crossDomainMessengerAddr).sendMessage(
            merkleDistributorL2Address,
            message,
            1000000   // within the free gas limit amount
        );
    }

}
