import chai, { expect } from "chai";
import { ethers } from "hardhat";
import { Contract } from "@ethersproject/contracts";
import { FakeContract, smock } from "@defi-wonderland/smock";
import { IExchanger } from "../../typechain/IExchanger";
import { ISynthetix } from "../../typechain/ISynthetix";
import { IAddressResolver } from "../../typechain/IAddressResolver";
import { IStakingRewards } from "../../typechain/IStakingRewards";

chai.use(smock.matchers);

describe("Exchanger Proxy", function () {
    let exchangerProxy: Contract,
        fakeStakingRewards: FakeContract<IStakingRewards>;
    before(async () => {

        //// Synthetix AddressResolver mocking. TODO: make reusable
        const fakeSynthetix = await smock.fake<ISynthetix>("ISynthetix");
        fakeSynthetix.exchangeWithTracking.returns(0);

        const fakeExchanger = await smock.fake<IExchanger>("IExchanger");
        fakeExchanger.feeRateForExchange.returns(0);

        const fakeAddressResolver = await smock.fake<IAddressResolver>(
            "IAddressResolver"
        );
        fakeAddressResolver.requireAndGetAddress.reverts();
        fakeAddressResolver.requireAndGetAddress
            .whenCalledWith(ethers.utils.formatBytes32String("Synthetix"), "Could not get Synthetix")
            .returns(fakeSynthetix.address);
            fakeAddressResolver.requireAndGetAddress
            .whenCalledWith(ethers.utils.formatBytes32String("Exchanger"), "Could not get Exchanger")
            .returns(fakeExchanger.address);
        ////

        fakeStakingRewards = await smock.fake<IStakingRewards>(
            "StakingRewards"
        );
        fakeStakingRewards.updateTraderScore.returns();

        const ExchangerProxy = await ethers.getContractFactory(
            "ExchangerProxy"
        );
        exchangerProxy = await ExchangerProxy.deploy(
            fakeAddressResolver.address,
            fakeStakingRewards.address
        );
        await exchangerProxy.deployed();

        return exchangerProxy;
    });

    it("updateTraderScore has been called", async function () {
        await exchangerProxy.exchangeWithTraderScoreTracking(
            ethers.utils.formatBytes32String("sUSD"),
            ethers.constants.One,
            ethers.utils.formatBytes32String("sETH"),
            ethers.constants.AddressZero,
            ethers.utils.formatBytes32String("KWENTA")
        );

        expect(fakeStakingRewards.updateTraderScore).to.have.been.calledOnce;
    });
});
