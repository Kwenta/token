// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './utils/ERC20.sol';
import './utils/Owned.sol';
import './interfaces/ISupplySchedule.sol';
import './interfaces/IKwenta.sol';

contract Kwenta is ERC20, Owned, IKwenta {
    /// @notice defines inflationary supply schedule, 
    /// according to which the KWENTA inflationary supply is released
    ISupplySchedule public supplySchedule;

    modifier onlySupplySchedule() {
        require(msg.sender == address(supplySchedule), "Only SupplySchedule can perform this action");
        _;
    }

    constructor(
        string memory name, 
        string memory symbol, 
        uint _initialSupply, 
        address _owner,
        address _treasuryDAO
    ) ERC20(name, symbol) Owned(_owner) {
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

    function setSupplySchedule(address _supplySchedule) override external onlyOwner {
        supplySchedule = ISupplySchedule(_supplySchedule);
    }

}