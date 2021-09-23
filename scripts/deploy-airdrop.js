const fs = require("fs");
const { MerkleTree } = require("merkletreejs");
const keccak256 = require("keccak256");
const { web3 } = require("hardhat");

const { getTargetAddress, setTargetAddress } = require("./snx-data/utils.js");
const historicalSnapshot = require("./snx-data/historical_snx.json");

async function deploy_airdrop() {
  const accounts = await ethers.getSigners();
  const networkObj = await ethers.provider.getNetwork();
  const network = networkObj.name;
  if (network === "homestead") {
    network = "mainnet";
  } else if (network === "unknown") {
    network = "localhost";
  }

  if (network !== "mainnet") {
    console.log("not on mainnet - using test snapshot");
    historicalSnapshot = require("./snx-data/historical_snx_test.json");
  }
  console.log("Network name:" + network);

  const owner = accounts[0];

  const ERC20 = await ethers.getContractFactory("ERC20");
  const kwenta = await ERC20.attach(kwentaAddress);
  const totalSupply = await kwenta.totalSupply();
  console.log("kwenta token total supply", totalSupply);

  const PERCENT_TO_STAKERS = 0.3;
  const AIRDROP_AMOUNT = totalSupply.mul(PERCENT_TO_STAKERS);
  const BASE_AMOUNT = new ethers.BigNumber.from(1);
  const historicalSnapshotData = Object.entries(historicalSnapshot);
  // the pro rata amount is calculated after everyone has received the base amount
  const PRO_RATA_AMOUNT = AIRDROP_AMOUNT.sub(
    BASE_AMOUNT.mul(historicalSnapshotData.length)
  );

  const userBalanceAndHashes = [];
  const userBalanceHashes = [];
  const totalStakingScore = historicalSnapshotData.reduce(
    (acc, [, stakingScore]) => acc.add(stakingScore),
    new ethers.BigNumber.from(0)
  );

  // merge all addresses into final snapshot
  // get list of leaves for the merkle trees using index, address and token balance
  // encode user address and balance using web3 encodePacked
  let duplicateCheckerSet = new Set();
  let i = 0;
  for (const [address, stakingScore] of historicalSnapshotData) {
    // new value is BASE_AMOUNT + stakingScore / totalStakingScore * PRO_RATA_AMOUNT
    const newValue = stakingScore
      .times(PRO_RATA_AMOUNT)
      .div(totalStakingScore)
      .add(BASE_AMOUNT)
      .round();

    if (duplicateCheckerSet.has(address)) {
      console.log(
        "duplicate found - this should never happens",
        "address",
        address,
        "skipped stakingScore",
        stakingScore
      );
      throw new Error(
        "duplicate entry found - should not happen or need to update script"
      );
    } else {
      duplicateCheckerSet.add(address);
    }
    const hash = keccak256(web3.utils.encodePacked(i, address, newValue));
    const balance = {
      address: address,
      balance: newValue,
      hash: hash,
      proof: "",
      index: i,
    };
    userBalanceHashes.push(hash);
    userBalanceAndHashes.push(balance);
    i++;
  }

  // create merkle tree
  const merkleTree = new MerkleTree(userBalanceHashes, keccak256, {
    sortLeaves: true,
    sortPairs: true,
  });

  for (const ubh in userBalanceAndHashes) {
    userBalanceAndHashes[ubh].proof = merkleTree.getHexProof(
      userBalanceAndHashes[ubh].hash
    );
  }
  fs.writeFileSync(
    `scripts/snx-data/${network}/airdrop-hashes.json`,
    JSON.stringify(userBalanceAndHashes),
    function (err) {
      if (err) return console.log(err);
    }
  );

  // Get tree root
  const root = merkleTree.getHexRoot();
  console.log("tree root:", root);

  const kwentaAddress = getTargetAddress("Kwenta", network);
  console.log("kwenta address:", kwentaAddress);

  // deploy Airdrop contract
  const Airdrop = await ethers.getContractFactory("Airdrop");
  const airdrop = await Airdrop.deploy(owner.address, kwentaAddress, root);
  await airdrop.deployed();

  await kwenta.transfer(airdrop.address, totalStakingScore);

  console.log("airdrop deployed at", airdrop.address);
  // update deployments.json file
  setTargetAddress("Airdrop", network, airdrop.address);

  await hre.run("verify:verify", {
    address: airdrop.address,
    constructorArguments: [owner.address, kwentaAddress, root],
  });
}

deploy_airdrop()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
