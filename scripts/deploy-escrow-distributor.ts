import { ethers } from "hardhat";
import { saveDeployments } from "./deploy";

import kwentaTestnetDeploy from "../deployments/optimistic-goerli/Kwenta.json";
import rewardEscrowTestnetDeploy from "../deployments/optimistic-goerli/RewardEscrow.json";

async function main() {
    const [deployer] = await ethers.getSigners();

    const EscrowDistributor = await ethers.getContractFactory(
        "EscrowDistributor"
    );

    const chain = await deployer.getChainId();

    // TODO: Add mainnet once deployed
    if (chain !== 420) throw new Error("Network not supported");

    const escrowDistributor = await EscrowDistributor.deploy(
        kwentaTestnetDeploy.address,
        rewardEscrowTestnetDeploy.address
    );

    await escrowDistributor.deployed();
    await saveDeployments("EscrowDistributor", escrowDistributor);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
