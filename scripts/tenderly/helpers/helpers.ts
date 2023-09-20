import { ethers, tenderly } from "hardhat";
import { provider } from "./constants";
import { BigNumber, Contract } from "ethers";
import { Interface } from "@ethersproject/abi";

/************************************************
 * @time
 ************************************************/

export const advanceTime = async (seconds: number) => {
    const params = [
        ethers.utils.hexValue(seconds), // hex encoded number of seconds
    ];
    const res = await provider.send("evm_increaseTime", params);

    console.log("time advanced:", res);
};

export const getLatestBlockTimestamp = async (): Promise<number> => {
    const currentBlock = await ethers.provider.getBlockNumber();
    const blockTimestamp = (await ethers.provider.getBlock(currentBlock))
        .timestamp;
    return blockTimestamp;
};

export const timeLog = (label: string, timestamp: number) => {
    console.log(`${label}: `, timestamp, new Date(timestamp * 1000));
};

/************************************************
 * @helpers
 ************************************************/

// TODO: refactor to use deployContract helper
export const deployUUPSProxy = async ({
    contractName,
    constructorArgs,
    initializerArgs,
}: {
    contractName: string;
    constructorArgs: unknown[];
    initializerArgs: unknown[];
}) => {
    const Factory = await ethers.getContractFactory(contractName);
    const implementation = await Factory.deploy(...constructorArgs);
    await implementation.deployed();
    await tenderly.verify({
        name: contractName,
        address: implementation.address,
    });

    // Deploy proxy
    const ERC1967ProxyExposed = await ethers.getContractFactory(
        "ERC1967ProxyExposed"
    );
    const initializerData = getInitializerData(
        Factory.interface,
        initializerArgs,
        undefined
    );
    const proxy = await ERC1967ProxyExposed.deploy(
        implementation.address,
        initializerData
    );
    await proxy.deployed();
    await tenderly.verify({
        name: "ERC1967ProxyExposed",
        address: proxy.address,
    });

    const wrappedProxy = await ethers.getContractAt(
        contractName,
        proxy.address
    );
    return [wrappedProxy, implementation];
};

export const deployContract = async ({
    contractName,
    constructorArgs,
}: {
    contractName: string;
    constructorArgs: unknown[];
}): Promise<Contract> => {
    const Factory = await ethers.getContractFactory(contractName);
    const contract = await Factory.deploy(...constructorArgs);
    await contract.deployed();
    await tenderly.verify({
        name: contractName,
        address: contract.address,
    });
    return contract;
};

export const getInitializerData = (
    contractInterface: Interface,
    args: unknown[],
    initializer?: string | false
): string => {
    if (initializer === false) {
        return "0x";
    }

    const allowNoInitialization =
        initializer === undefined && args.length === 0;
    initializer = initializer ?? "initialize";

    try {
        const fragment = contractInterface.getFunction(initializer);
        return contractInterface.encodeFunctionData(fragment, args);
    } catch (e: unknown) {
        if (e instanceof Error) {
            if (
                allowNoInitialization &&
                e.message.includes("no matching function")
            ) {
                return "0x";
            }
        }
        throw e;
    }
};

export const sendTransaction = async ({
    contractName,
    contractAddress,
    functionName,
    functionArgs,
    from,
}: {
    contractName: string;
    contractAddress: string;
    functionName: string;
    functionArgs: unknown[];
    from: string;
}) => {
    const contract = await ethers.getContractAt(contractName, contractAddress);

    const unsignedTx = await contract.populateTransaction[functionName](
        ...functionArgs
    );

    const transactionParameters = [
        {
            to: contract.address,
            from: from,
            data: unsignedTx.data,
        },
    ];

    await provider.send("eth_sendTransaction", transactionParameters);
};

export const logTransaction = (
    contractName: string,
    functionName: string,
    functionArgs: unknown[]
) => {
    let log = `${contractName}: ${functionName} called with:`;
    console.log(extendLog(log), ...functionArgs);
};

export const extendLog = (log: string) => {
    while (log.length < 53) log += " ";
    return log;
};

export const printEntries = (entries: BigNumber[]) => {
    const entryIDs = entries.map((x) => x.toNumber());
    let list = "[";
    for (let i = 0; i < entryIDs.length; i++) {
        if (i == entryIDs.length - 1) {
            list += `${entryIDs[i]}`;
        } else {
            list += `${entryIDs[i]},`;
        }
    }
    list += "]";
    console.log(list);
};
