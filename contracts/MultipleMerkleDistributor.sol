// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./utils/Owned.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./interfaces/IRewardEscrow.sol";
import "./interfaces/IMultipleMerkleDistributor.sol";
import {ICrossDomainMessenger} from "@eth-optimism/contracts/libraries/bridge/ICrossDomainMessenger.sol";

/// @title Kwenta MultipleMerkleDistributor
/// @author JaredBorders and JChiaramonte7
/// @notice Facilitates trading incentives distribution over multiple periods.
contract MultipleMerkleDistributor is IMultipleMerkleDistributor, Owned {
    /// @notice escrow for tokens claimed
    address public immutable override rewardEscrow;

    /// @notice token to be distributed (KWENTA)
    address public immutable override token;

    /// @notice an index that is incremented for each new merkle root
    uint256 distributionEpoch;

    /// @notice the merkle root of the merkle tree containing account balances available to claim
    mapping(uint256 => bytes32) public override merkleRoots;

    /// @notice this is a packed array of booleans
    mapping(uint256 => mapping(uint256 => uint256)) private claimedBitMaps;

    /// @notice set addresses for deployed rewardEscrow and KWENTA.
    /// Establish merkle root for verification
    /// @param _owner: designated owner of this contract
    /// @param _token: address of erc20 token to be distributed
    /// @param _rewardEscrow: address of kwenta escrow for tokens claimed
    constructor(
        address _owner,
        address _token,
        address _rewardEscrow
    ) Owned(_owner) {
        token = _token;
        rewardEscrow = _rewardEscrow;
    }

    function newMerkleRoot(bytes32 _merkleRoot) external onlyOwner {
        merkleRoots[distributionEpoch] = _merkleRoot;
        emit MerkleRootAdded(distributionEpoch);
        distributionEpoch++;
    }

    /// @notice determine if indexed claim has been claimed
    /// @param index: used for claim managment
    /// @param epoch: distribution index to check
    /// @return true if indexed claim has been claimed
    function isClaimed(uint256 index, uint256 epoch) public view override returns (bool) {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        uint256 claimedWord = claimedBitMaps[epoch][claimedWordIndex];
        uint256 mask = (1 << claimedBitIndex);
        return claimedWord & mask == mask;
    }

    /// @notice set claimed status for indexed claim to true
    /// @param index: used for claim managment
    /// @param epoch: distribution index to check
    function _setClaimed(uint256 index, uint256 epoch) private {
        uint256 claimedWordIndex = index / 256;
        uint256 claimedBitIndex = index % 256;
        claimedBitMaps[epoch][claimedWordIndex] =
            claimedBitMaps[epoch][claimedWordIndex] |
            (1 << claimedBitIndex);
    }

    /// @notice attempt to claim as `account` and escrow KWENTA for `account`
    /// @param index: used for merkle tree managment and verification
    /// @param account: address used for escrow entry
    /// @param amount: $KWENTA amount to be escrowed
    /// @param merkleProof: off-chain generated proof of merkle tree inclusion
    /// @param epoch: distribution index to check
    function claim(
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof,
        uint256 epoch
    ) external override {
        require(!isClaimed(index, epoch), "MultipleMerkleDistributor: Drop already claimed.");

        // verify the merkle proof
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(
            MerkleProof.verify(merkleProof, merkleRoots[epoch], node),
            "MultipleMerkleDistributor: Invalid proof."
        );

        // mark it claimed and send the token to RewardEscrow
        _setClaimed(index, epoch);
        IERC20(token).approve(rewardEscrow, amount);
        IRewardEscrow(rewardEscrow).createEscrowEntry(
            account,
            amount,
            52 weeks
        );

        emit Claimed(index, account, amount, epoch);
    }
}
