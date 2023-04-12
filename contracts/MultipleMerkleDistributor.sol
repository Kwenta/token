// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "./utils/Owned.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "./interfaces/IRewardEscrow.sol";
import "./interfaces/IMultipleMerkleDistributor.sol";

/// @title Kwenta MultipleMerkleDistributor
/// @author JaredBorders and JChiaramonte7
/// @notice Facilitates trading incentives distribution over multiple periods.
contract MultipleMerkleDistributor is IMultipleMerkleDistributor, Owned {
    using SafeERC20 for IERC20;
    /// @inheritdoc IMultipleMerkleDistributor
    address public immutable override token;

    /// @inheritdoc IMultipleMerkleDistributor
    mapping(uint256 => bytes32) public override merkleRoots;

    /// @notice an epoch to packed array of claimed booleans mapping
    mapping(uint256 => mapping(uint256 => uint256)) private claimedBitMaps;

    /// @notice set addresses ERC20 contract
    /// Establish merkle root for verification
    /// @param _owner: designated owner of this contract
    /// @param _token: address of erc20 token to be distributed
    constructor(address _owner, address _token) Owned(_owner) {
        token = _token;
    }

    /// @inheritdoc IMultipleMerkleDistributor
    function setMerkleRootForEpoch(bytes32 merkleRoot, uint256 epoch)
        external
        override
        onlyOwner
    {
        merkleRoots[epoch] = merkleRoot;
        emit MerkleRootModified(epoch);
    }

    /// @inheritdoc IMultipleMerkleDistributor
    function isClaimed(uint256 index, uint256 epoch)
        public
        view
        override
        returns (bool)
    {
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

    /// @inheritdoc IMultipleMerkleDistributor
    function claim(
        uint256 index,
        address account,
        uint256 amount,
        bytes32[] calldata merkleProof,
        uint256 epoch
    ) public override {
        require(
            !isClaimed(index, epoch),
            "MultipleMerkleDistributor: Drop already claimed."
        );

        // verify the merkle proof
        bytes32 node = keccak256(abi.encodePacked(index, account, amount));
        require(
            MerkleProof.verify(merkleProof, merkleRoots[epoch], node),
            "MultipleMerkleDistributor: Invalid proof."
        );

        // mark it claimed and send the token
        _setClaimed(index, epoch);
        IERC20(token).safeTransfer(account, amount);

        emit Claimed(index, account, amount, epoch);
    }

    /// @inheritdoc IMultipleMerkleDistributor
    function claimMultiple(Claims[] calldata claims) external override {
        uint256 cacheLength = claims.length;
        for (uint256 i = 0; i < cacheLength; ) {
            claim(
                claims[i].index,
                claims[i].account,
                claims[i].amount,
                claims[i].merkleProof,
                claims[i].epoch
            );
            unchecked {
                ++i;
            }
        }
    }
}
