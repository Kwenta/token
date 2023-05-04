//SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "./utils/ERC20.sol";
import "./interfaces/IRewardEscrow.sol";
import "./interfaces/IKwenta.sol";

contract AelinDistribution is ERC20 {
    /// @notice kwenta token contract
    IKwenta private immutable kwenta;

    /// @notice rewards escrow contract
    IRewardEscrow public immutable rewardEscrow;

    constructor(
        string memory _name,
        string memory _symbol,
        address _kwenta,
        address _rewardEscrowAddr
    ) ERC20(_name, _symbol) {
        kwenta = IKwenta(_kwenta);
        rewardEscrow = IRewardEscrow(_rewardEscrowAddr);
    }

    /**
     *   Receive Kwenta from user, then mint
     *   redeemable escrowed Kwenta and give
     *   to user.
     */
    function issueRedeemable1YR(uint amount) public payable {
        require(
            kwenta.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        _mint(msg.sender, amount);
    }

    /**
     *   call the escrow contract to send the KWENTA
     *   in here, to go there and be locked for a year
     */
    function redeemEscrow1YR(uint amount) public payable {
        _burn(msg.sender, amount);

        // Transfers kwenta from here to RewardEscrow.sol
        kwenta.approve(address(rewardEscrow), amount);
        rewardEscrow.createEscrowEntry(msg.sender, amount, 52 weeks);
    }
}
