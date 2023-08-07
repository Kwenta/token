import { BigNumber } from "@ethersproject/bignumber";
import { expect } from "chai";
import { ethers, network } from "hardhat";
import { Interface } from "@ethersproject/abi";

export const onlyGivenAddressCanInvoke = async (
    call: any, // TODO: look into typechain to grab types
    args: any,
    accounts: String[],
    address = undefined,
    skipPassCheck = false,
    reason = undefined
) => {
    for (const user of accounts) {
        if (user === address) {
            continue;
        }

        if (reason) {
            await expect(call(...args, { from: user })).to.be.revertedWith(
                reason
            );
        } else {
            await expect(call(...args, { from: user })).to.be.reverted;
        }
    }
    if (!skipPassCheck && address) {
        await call(...args, { from: address });
    }
};

/**
 *  Gets the time of the last block.
 */
export const currentTime = async () => {
    const { timestamp } = await ethers.provider.getBlock("latest");
    return timestamp;
};

/**
 *  Increases the time in the EVM.
 *  @param seconds Number of seconds to increase the time by
 */
export const fastForward = async (seconds: number | BigNumber) => {
    // It's handy to be able to be able to pass big numbers in as we can just
    // query them from the contract, then send them back. If not changed to
    // a number, this causes much larger fast forwards than expected without error.
    if (ethers.BigNumber.isBigNumber(seconds)) seconds = seconds.toNumber();

    // And same with strings.
    if (typeof seconds === "string") seconds = parseFloat(seconds);

    await network.provider.send("evm_increaseTime", [seconds]);

    await network.provider.send("evm_mine");
};

/**
 *  Increases the time in the EVM to as close to a specific date as possible
 *  NOTE: Because this operation figures out the amount of seconds to jump then applies that to the EVM,
 *  sometimes the result can vary by a second or two depending on how fast or slow the local EVM is responding.
 *  @param time Date object representing the desired time at the end of the operation
 */
export const fastForwardTo = async (time: Date) => {
    const timestamp = await currentTime();
    const now = new Date(timestamp * 1000);
    if (time < now)
        throw new Error(
            `Time parameter (${time}) is less than now ${now}. You can only fast forward to times in the future.`
        );

    const secondsBetween = Math.floor((time.getTime() - now.getTime()) / 1000);

    await fastForward(secondsBetween);
};

/**
 *  Use to send a TX from another smart contract to bypass access modifiers
 *  Impersonates as an EOA
 *  @param address Address of contract
 */
export const impersonate = async (address: string) => {
    await network.provider.request({
        method: "hardhat_impersonateAccount",
        params: [address],
    });
    // Provide with ETH for TX
    await network.provider.request({
        method: "hardhat_setBalance",
        params: [address, ethers.utils.parseEther("10").toHexString()],
    });
    return await ethers.getSigner(address);
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
}
