import { wei } from "@synthetixio/wei";
import { ethers } from "ethers";

export type SerializedWei = {
    p: number;
    bn: {
        type: string;
        hex: string;
    };
};

// Older versions of wei serialized Wei as objects
export const reconstructWei = (weiObject: SerializedWei) =>
    wei(ethers.BigNumber.from(weiObject.bn.hex).toString(), weiObject.p, true);
