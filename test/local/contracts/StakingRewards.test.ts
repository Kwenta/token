import { expect } from "chai";
import hre, { ethers } from "hardhat";
import { Contract } from "@ethersproject/contracts";
import { FakeContract, smock } from "@defi-wonderland/smock";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { SupplySchedule } from "../../../typechain/SupplySchedule";
import { StakingRewards } from "../../../typechain/StakingRewards";
import { RewardEscrow } from "../../../typechain/RewardEscrow";

describe("StakingRewards", () => {
    // contracts
    let stakingRewards: Contract;
    let supplySchedule: Contract;
    let rewardEscrow: Contract;

    // signers
    let signers: SignerWithAddress[];

    before(async () => {
        signers = await ethers.getSigners();
    })
});
