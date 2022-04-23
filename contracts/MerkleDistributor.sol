// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./interfaces/IRewardEscrow.sol";
import "./interfaces/IMerkleDistributor.sol";

import { ICrossDomainMessenger } from 
    "@eth-optimism/contracts/libraries/bridge/ICrossDomainMessenger.sol";

contract MerkleDistributor is IMerkleDistributor {
    // escrow for tokens claimed
    address public immutable override rewardEscrow;

    address public immutable override token;
    bytes32 public immutable override merkleRoot;

    // communication between L1 and L2 is enabled by two special smart contracts called the "messengers"
    // and below is the address for the messenger on L2
    address private crossDomainMessengerAddr = 0x4200000000000000000000000000000000000007;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    constructor(address _token, address _rewardEscrow, bytes32 _merkleRoot) {
        token = _token;
        rewardEscrow = _rewardEscrow;
        merkleRoot = _merkleRoot;
    }

    function isClaimed(uint256 index) public view override returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMap[claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    function _setClaimed(uint256 index) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
    }

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof) external override {
        require(!isClaimed(index), 'MerkleDistributor: Drop already claimed.');

        // Verify the merkle proof.
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), 'MerkleDistributor: Invalid proof.');

        // Mark it claimed and send the token to RewardEscrow
        _setClaimed(index);
        IERC20(token).approve(rewardEscrow, amount);
        IRewardEscrow(rewardEscrow).createEscrowEntry(account, amount, 52 weeks);
        
        emit Claimed(index, account, amount);
    }

    function claimToAddress(uint256 index, address destAccount, uint256 amount, bytes32[] calldata merkleProof) external override {
        require(!isClaimed(index), 'MerkleDistributor: Drop already claimed.');
        require(msg.sender == crossDomainMessengerAddr, 
            "MerkleDistributor: Only the OVM-ICrossDomainMessenger can call this function"
        );

        // caller address from L1 (effectively the msg.sender on L1)
        address caller = ICrossDomainMessenger(crossDomainMessengerAddr).xDomainMessageSender();

        // Verify the merkle proof with the L1 caller's address
        bytes32 node = keccak256(abi.encodePacked(index, caller, amount));
        require(MerkleProof.verify(merkleProof, merkleRoot, node), 'MerkleDistributor: Invalid proof.');

        // Mark it claimed and send the token to RewardEscrow
        _setClaimed(index);
        IERC20(token).approve(rewardEscrow, amount);
        // @notice destAccount is NOT necessarily the caller's address
        IRewardEscrow(rewardEscrow).createEscrowEntry(destAccount, amount, 52 weeks);
        
        emit Claimed(index, caller, amount);
    }
}