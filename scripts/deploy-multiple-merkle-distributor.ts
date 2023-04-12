import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { saveDeployments, verify } from "./utils";

const REWARD_DISTRIBUTOR = "0xbA49be134D5dA836EC1be90A4E29c237a3a758A6";
const OP_TOKEN_ADDRESS = "0x4200000000000000000000000000000000000042";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    const tradingRewards = await deployMultipleMerkleDistributor(
        deployer,
        OP_TOKEN_ADDRESS
    );

    await tradingRewards.nominateNewOwner(REWARD_DISTRIBUTOR);
    console.log(
        "TradingRewards nominated owner:         ",
        await tradingRewards.nominatedOwner()
    );
}

async function deployMultipleMerkleDistributor(
    owner: SignerWithAddress,
    token: string
) {
    const MultipleMerkleDistributor = await ethers.getContractFactory(
        "MultipleMerkleDistributor"
    );
    const multipleMerkleDistributor = await MultipleMerkleDistributor.deploy(
        owner.address,
        token
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
        [owner.address, token],
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
