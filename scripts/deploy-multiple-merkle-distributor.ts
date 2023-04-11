import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { saveDeployments, verify } from "./utils";
import { address as KWENTA_ADDRESS } from "../deployments/optimistic-mainnet/Kwenta.json";

const REWARD_DISTRIBUTOR = "0x246100EC9dfCF22194316A187B38905906539B41";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    const tradingRewards = await deployMultipleMerkleDistributor(
        deployer,
        KWENTA_ADDRESS
    );

    await tradingRewards.nominateNewOwner(REWARD_DISTRIBUTOR);
    console.log(
        "TradingRewards nominated owner:         ",
        await tradingRewards.nominatedOwner()
    );
}

async function deployMultipleMerkleDistributor(
    owner: SignerWithAddress,
    kwenta: string
) {
    const MultipleMerkleDistributor = await ethers.getContractFactory(
        "MultipleMerkleDistributor"
    );
    const multipleMerkleDistributor = await MultipleMerkleDistributor.deploy(
        owner.address,
        kwenta
    );
    await multipleMerkleDistributor.deployed();
    await saveDeployments(
        "MultipleMerkleDistributor",
        multipleMerkleDistributor
    );
    console.log(
        "MultipleMerkleDistributor deployed to:        ",
        multipleMerkleDistributor.address
    );

    await verify(
        multipleMerkleDistributor.address,
        [owner.address, kwenta],
        "contracts/MultipleMerkleDistributor.sol:MultipleMerkleDistributor" // to prevent bytecode clashes with contracts-exposed versions
    );

    return multipleMerkleDistributor;
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
