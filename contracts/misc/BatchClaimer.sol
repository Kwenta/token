// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../interfaces/IMultipleMerkleDistributor.sol";

contract BatchClaimer {
    
    function claimMultiple(
        IMultipleMerkleDistributor[] calldata _distributors,
        IMultipleMerkleDistributor.Claims[][] calldata _claims
    ) external {
        require(_distributors.length == _claims.length, "BatchClaimer: invalid input");
        for (uint256 i = 0; i < _distributors.length; i++) {
            _distributors[i].claimMultiple(_claims[i]);
        }
    }
}
