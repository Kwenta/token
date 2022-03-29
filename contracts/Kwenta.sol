// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './utils/ERC20.sol';
import './utils/Owned.sol';
import './interfaces/ISupplySchedule.sol';
import './interfaces/IKwenta.sol';

contract Kwenta is ERC20, Owned, IKwenta {

    ISupplySchedule immutable supplySchedule;

    constructor(
        string memory name, 
        string memory symbol, 
        uint _initialSupply, 
        address _owner,
        address _treasuryDAO,
        address _supplySchedule
    ) ERC20(name, symbol) Owned(_owner) {
        supplySchedule = ISupplySchedule(_supplySchedule);
        // Provide treasury with 100% of the initial supply
        _mint(_treasuryDAO, _initialSupply);
    }

    // Mints inflationary supply
    function mint(address account, uint amount) override external onlySupplySchedule {
        _mint(account, amount);
    }

    function burn(uint amount) override external {
        _burn(msg.sender, amount);
    }

    modifier onlySupplySchedule() {
        require(msg.sender == address(supplySchedule), "Only SupplySchedule can perform this action");
        _;
    }

}