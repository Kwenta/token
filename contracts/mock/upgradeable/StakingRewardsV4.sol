// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./StakingRewardsV3.sol";

contract StakingRewardsV4 is StakingRewardsV3 {
    uint16 private foo;

    function setFoo(uint16 _foo) public onlyOwner {
        foo = _foo;
    }

    function getFoo() public view returns (uint16) {
        return foo;
    }
}
