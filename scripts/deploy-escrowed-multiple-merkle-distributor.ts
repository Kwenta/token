import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { ethers } from "hardhat";
import { saveDeployments, verify } from "./utils";
import { address as KWENTA_ADDRESS } from "../deployments/optimistic-mainnet/Kwenta.json";

const REWARD_DISTRIBUTOR = "0x246100EC9dfCF22194316A187B38905906539B41";
const REWARD_ESCROW_ADDRESS = "0xb2a20fCdc506a685122847b21E34536359E94C56";

async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);
    console.log("Account balance:", (await deployer.getBalance()).toString());

    const tradingRewards = await deployEscrowedMultipleMerkleDistributor(
        deployer,
        KWENTA_ADDRESS,
        REWARD_ESCROW_ADDRESS
    );

    await tradingRewards.nominateNewOwner(REWARD_DISTRIBUTOR);
    console.log(
        "TradingRewards nominated owner:         ",
        await tradingRewards.nominatedOwner()
    );
}

async function deployEscrowedMultipleMerkleDistributor(
    owner: SignerWithAddress,
    kwenta: string,
    rewardEscrow: string
) {
    const EscrowedMultipleMerkleDistributor = await ethers.getContractFactory(
        "EscrowedMultipleMerkleDistributor"
    );
    const escrowedMultipleMerkleDistributor =
        await EscrowedMultipleMerkleDistributor.deploy(
            owner.address,
            kwenta,
            rewardEscrow
        );
    await escrowedMultipleMerkleDistributor.deployed();
    await saveDeployments(
        "EscrowedMultipleMerkleDistributor",
        escrowedMultipleMerkleDistributor
    );
    console.log(
        "EscrowedMultipleMerkleDistributor deployed to:        ",
        escrowedMultipleMerkleDistributor.address
    );

    await verify(
        escrowedMultipleMerkleDistributor.address,
        [owner.address, kwenta, rewardEscrow],
        "contracts/EscrowedMultipleMerkleDistributor.sol:EscrowedMultipleMerkleDistributor" // to prevent bytecode clashes with contracts-exposed versions
    );

    return escrowedMultipleMerkleDistributor;
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
