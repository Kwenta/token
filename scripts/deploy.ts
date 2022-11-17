// We require the Hardhat Runtime Environment explicitly here. This is optional
// but useful for running the script in a standalone fashion through `node <script>`.
//
// When running the script with `npx hardhat run <script>` you'll find the Hardhat
// Runtime Environment's members available in the global scope.
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { wei } from "@synthetixio/wei";
import { Contract } from "ethers";
import hre, { ethers } from "hardhat";
import { saveDeployments, verify } from "./utils";

const isLocal = hre.network.name == "localhost";
const isTestnet = hre.network.name == "optimistic-goerli";

const TEST_WALLET = "0xC2ecD777d06FFDF8B3179286BEabF52B67E9d991";
const MULTISIG = isTestnet
    ? TEST_WALLET
    : "0xF510a2Ff7e9DD7e18629137adA4eb56B9c13E885";
const TREASURY_DAO = isTestnet
    ? TEST_WALLET
    : "0x82d2242257115351899894eF384f779b5ba8c695";
const INITIAL_SUPPLY = 313373;
const VKWENTA = "0x6789D8a7a7871923Fc6430432A602879eCB6520a";

async function main() {
    const [deployer] = await ethers.getSigners();

    // ========== DEPLOYMENT ========== */

    console.log("\n💥 Beginning deployments...");
    const kwenta = await deployKwenta(deployer);
    const safeDecimalMath = await deploySafeDecimalMath();
    const supplySchedule = await deploySupplySchedule(
        deployer,
        safeDecimalMath
    );
    const rewardEscrow = await deployRewardEscrow(deployer, kwenta);
    const stakingRewards = await deployStakingRewards(
        deployer,
        kwenta,
        rewardEscrow,
        supplySchedule
    );
    const vKwentaRedeemer = await deployvKwentaRedeemer(kwenta);
    const tradingRewards = await deployMultipleMerkleDistributor(
        deployer,
        kwenta,
        rewardEscrow
    );
    console.log("✅ Deployments complete!");

    // ========== SETTERS ========== */

    console.log("\n🔩 Configuring setters...");
    // set SupplySchedule for kwenta
    await kwenta.setSupplySchedule(supplySchedule.address);
    console.log(
        "Kwenta: SupplySchedule address set to:          ",
        await kwenta.supplySchedule()
    );

    // set KWENTA address in SupplySchedule
    await supplySchedule.setKwenta(kwenta.address);
    console.log(
        "SupplySchedule: Kwenta address set to:          ",
        await supplySchedule.kwenta()
    );

    // set StakingRewards address in SupplySchedule
    await supplySchedule.setStakingRewards(stakingRewards.address);
    console.log(
        "SupplySchedule: StakingRewards address set to:  ",
        await supplySchedule.stakingRewards()
    );

    // set TradingRewards (i.e. MultipleMerkleDistributor) address in SupplySchedule
    await supplySchedule.setTradingRewards(tradingRewards.address);
    console.log(
        "SupplySchedule: TradingRewards address set to:  ",
        await supplySchedule.tradingRewards()
    );

    // set StakingRewards address in RewardEscrow
    await rewardEscrow.setTreasuryDAO(TREASURY_DAO);
    console.log(
        "RewardEscrow: TreasuryDAO address set to:       ",
        await rewardEscrow.treasuryDAO()
    );
    console.log("✅ Setters set!");

    // set StakingRewards address in RewardEscrow
    await rewardEscrow.setStakingRewards(stakingRewards.address);
    console.log(
        "RewardEscrow: StakingRewards address set to:    ",
        await rewardEscrow.stakingRewards()
    );
    console.log("✅ Setters set!");

    /*
     * @TODO: Deploy ControlL2MerkleDistributor on L1 passing deployed merkleDistributor as constructor param
     * @TODO: Call MerkleDistributor.setControlL2MerkleDistributor(), setting ControlL2MerkleDistributor L1 address
     */

    // ========== DISTRIBUTION ========== */

    // Send KWENTA to respective contracts
    console.log("\n🎉 Distributing KWENTA...");
    await distributeKWENTA(deployer, kwenta, vKwentaRedeemer);
    console.log("✅ KWENTA distributed!");

    // ========== OWNER NOMINATION ========== */

    console.log("\n🔒 Nominating multisig as owner...");
    await kwenta.nominateNewOwner(MULTISIG);
    console.log(
        "Kwenta nominated owner:                 ",
        await kwenta.nominatedOwner()
    );
    await tradingRewards.nominateNewOwner(MULTISIG);
    console.log(
        "TradingRewards nominated owner:         ",
        await tradingRewards.nominatedOwner()
    );
    await supplySchedule.nominateNewOwner(MULTISIG);
    console.log(
        "SupplySchedule nominated owner:         ",
        await supplySchedule.nominatedOwner()
    );
    await rewardEscrow.nominateNewOwner(MULTISIG);
    console.log(
        "RewardEscrow nominated owner:           ",
        await rewardEscrow.nominatedOwner()
    );
    await stakingRewards.nominateNewOwner(MULTISIG);
    console.log(
        "StakingRewards nominated owner:         ",
        await stakingRewards.nominatedOwner()
    );
    console.log("✅ Nomination complete!\n");
}

/************************************************
 * @deployers
 ************************************************/

async function deploySafeDecimalMath() {
    // deploy SafeDecimalMath
    const SafeDecimalMath = await ethers.getContractFactory("SafeDecimalMath");
    const safeDecimalMath = await SafeDecimalMath.deploy();
    await safeDecimalMath.deployed();
    await saveDeployments("SafeDecimalMath", safeDecimalMath);

    if (!isLocal) {
        await hre.run("verify:verify", {
            address: safeDecimalMath.address,
            noCompile: true,
        });
    }

    return safeDecimalMath;
}

async function deployKwenta(owner: SignerWithAddress) {
    const Kwenta = await ethers.getContractFactory("Kwenta");
    const kwenta = await Kwenta.deploy(
        "Kwenta",
        "KWENTA",
        wei(INITIAL_SUPPLY).toBN(),
        owner.address,
        owner.address // Send KWENTA to deployer first
    );
    await kwenta.deployed();
    await saveDeployments("Kwenta", kwenta);
    console.log("KWENTA token deployed to:          ", kwenta.address);

    await verify(kwenta.address, [
        "Kwenta",
        "KWENTA",
        wei(INITIAL_SUPPLY).toBN(),
        owner.address,
        owner.address,
    ]);

    return kwenta;
}

async function deploySupplySchedule(
    owner: SignerWithAddress,
    safeDecimalMath: Contract
) {
    const SupplySchedule = await ethers.getContractFactory("SupplySchedule", {
        libraries: {
            SafeDecimalMath: safeDecimalMath.address,
        },
    });
    const supplySchedule = await SupplySchedule.deploy(
        owner.address,
        TREASURY_DAO
    );
    await supplySchedule.deployed();
    await saveDeployments("SupplySchedule", supplySchedule);
    console.log("SupplySchedule deployed to:        ", supplySchedule.address);

    await verify(supplySchedule.address, [owner.address, TREASURY_DAO]);

    return supplySchedule;
}

async function deployRewardEscrow(owner: SignerWithAddress, kwenta: Contract) {
    const RewardEscrow = await ethers.getContractFactory("RewardEscrow");
    const rewardEscrow = await RewardEscrow.deploy(
        owner.address,
        kwenta.address
    );
    await rewardEscrow.deployed();
    await saveDeployments("RewardEscrow", rewardEscrow);
    console.log("RewardEscrow deployed to:          ", rewardEscrow.address);

    await verify(rewardEscrow.address, [owner.address, kwenta.address]);

    return rewardEscrow;
}

async function deployStakingRewards(
    owner: SignerWithAddress,
    kwenta: Contract,
    rewardEscrow: Contract,
    supplySchedule: Contract
) {
    const StakingRewards = await ethers.getContractFactory("contracts/StakingRewards.sol:StakingRewards");
    const stakingRewards = await StakingRewards.connect(owner).deploy(
        kwenta.address,
        rewardEscrow.address,
        supplySchedule.address
    );
    await stakingRewards.deployed();
    await saveDeployments("StakingRewards", stakingRewards);
    console.log("StakingRewards deployed to:        ", stakingRewards.address);

    await verify(stakingRewards.address, [
        kwenta.address,
        rewardEscrow.address,
        supplySchedule.address,
    ]);

    return stakingRewards;
}

async function deployvKwentaRedeemer(kwenta: Contract) {
    const VKwentaRedeemer = await ethers.getContractFactory("vKwentaRedeemer");
    const vKwentaRedeemer = await VKwentaRedeemer.deploy(
        VKWENTA,
        kwenta.address
    );
    await vKwentaRedeemer.deployed();
    await saveDeployments("vKwentaRedeemer", vKwentaRedeemer);
    console.log("vKwentaRedeemer deployed to:       ", vKwentaRedeemer.address);

    await verify(
        vKwentaRedeemer.address,
        [VKWENTA, kwenta.address],
        "contracts/vKwentaRedeemer.sol:vKwentaRedeemer" // to prevent bytecode clashes with contracts-exposed versions
    );

    return vKwentaRedeemer;
}

async function deployMultipleMerkleDistributor(
    owner: SignerWithAddress,
    kwenta: Contract,
    rewardEscrow: Contract
) {
    const MultipleMerkleDistributor = await ethers.getContractFactory(
        "MultipleMerkleDistributor"
    );
    const multipleMerkleDistributor = await MultipleMerkleDistributor.deploy(
        owner.address,
        kwenta.address,
        rewardEscrow.address
    );
    await multipleMerkleDistributor.deployed();
    await saveDeployments(
        "MultipleMerkleDistributor",
        multipleMerkleDistributor
    );
    console.log(
        "TradingRewards deployed to:        ",
        multipleMerkleDistributor.address
    );

    await verify(
        multipleMerkleDistributor.address,
        [owner.address, kwenta.address, rewardEscrow.address],
        "contracts/MultipleMerkleDistributor.sol:MultipleMerkleDistributor" // to prevent bytecode clashes with contracts-exposed versions
    );

    return multipleMerkleDistributor;
}

/************************************************
 * @distributions
 ************************************************/

async function distributeKWENTA(
    signer: SignerWithAddress,
    kwenta: Contract,
    vKwentaRedeemer: Contract
) {
    // Transfer 100% KWENTA to Treasury
    await kwenta.transfer(TREASURY_DAO, wei(INITIAL_SUPPLY).toBN());

    console.log(
        "TreasuryDAO balance:         ",
        ethers.utils.formatEther(await kwenta.balanceOf(TREASURY_DAO))
    );
    console.log(
        "Final signer balance:        ",
        ethers.utils.formatEther(await kwenta.balanceOf(signer.address))
    );
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
    .then(() => process.exit(0))
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });
