import { expect } from "chai";
import { ethers } from "hardhat";

const loadSetup = () => {
    before("Deploy contracts", async () => {
        // TODO: Deploy contracts
    });
};

describe("Stake", () => {
    describe("Regular staking", async () => {
        loadSetup();
        it("Stake and withdraw all", async () => {
            // TODO: expect same tokens back
        });
        it("Stake and claim: ", async () => {
            // TODO: expect 0 rewards
        });
        it("Wait then claim", async () => {
            // TODO: expect > 0 rewards appended in escrow
        });
        it("Exit with half", async () => {
            // TODO: expect half tokens back no rewards
        });
        it("Wait, exit with remaining half", async () => {
            // TODO: expect same tokens back, > 0 rewards appended in escrow
        });
    });
    describe("Escrow staking", async () => {
        loadSetup();
        before("Create new escrow entry", async () => {
            // TODO: stake some equivalent kwenta for staker 1 and staker 2
        });
        it("Stake escrowed kwenta", async () => {
            // TODO: expect balance of staked escrow to be > 0
        });
        it("Wait, claim rewards", async () => {
            // TODO: expect balance of staked escrow to be > 0
        });
        it("Unstake escrowed kwenta", async () => {
            // TODO: expect balance of staked escrow 0
        });
    });
    describe("Staking w/ trading rewards", async () => {
        loadSetup();
        before("Stake kwenta", async () => {
            // TODO: stake some equivalent kwenta for staker 1 and staker 2
        });
        it("Execute trade on synthetix through proxy", async () => {
            // TODO: expect traderScore to have been updated for staker 1
        });
        it("Wait, and then claim kwenta for both stakers", async () => {
            // TODO: expect staker 1 to have greater rewards
        });
    });
});
