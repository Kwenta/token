// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import './ERC20.sol';

contract Kwenta is ERC20 {

    constructor(
        string memory name, 
        string memory symbol, 
        uint _initialSupply, 
        address _treasuryDAO
    ) ERC20(name, symbol) {
        // Treasury DAO 60%
        _mint(_treasuryDAO, _initialSupply * 60 / 100);
        // TODO: Transfer to respective distributions:
        // Synthetix Staker Airdrop 15%
        // SX/Kwenta Airdrop 2.5%
        // Staker Ongoing Distribution 15%
        // Trader Ongoing Distribution 2.5%
        // Aelin 5%
    }

    function mintInflationary(address to, uint256 amount) public virtual {
        // TODO: Mint amount from SupplySchedule.sol
        // _mint(to, amount);
    }

}