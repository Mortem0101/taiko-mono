import { getContract } from '@wagmi/core';

import { crossChainSyncABI } from '$abi';
import { routingContractsMap } from '$bridgeConfig';
import { publicClient } from '$libs/wagmi';

import { type BridgeTransaction, MessageStatus } from './types';

// How does getSyncedSnippet work behind the scene? 
export async function isTransactionProcessable(bridgeTx: BridgeTransaction) {
  const { receipt, message, srcChainId, destChainId, status } = bridgeTx;

  // Without these guys there is no way we can process this
  // bridge transaction. The receipt is needed in order to compare
  // the block number with the cross chain block number.
  if (!receipt || !message) return false;

  // Any other status that's not NEW we assume this bridge tx
  // has already been processed (was processable)
  // TODO: do better job here as this is to make the UI happy
  if (status !== MessageStatus.NEW) return true;

  const destCrossChainSyncAddress = routingContractsMap[Number(destChainId)][Number(srcChainId)].crossChainSyncAddress;

  try {
    const destCrossChainSyncContract = getContract({
      address: destCrossChainSyncAddress,
      abi: crossChainSyncABI,
      chainId: Number(destChainId),
    });

    console.log("isTransactionProcessable srcChainId", srcChainId);
    console.log("isTransactionProcessable destChainId", destChainId);
    console.log("isTransactionProcessable destCrossChainSyncAddress", destCrossChainSyncAddress);
    console.log("isTransactionProcessable destCrossChainSyncContract", destCrossChainSyncContract);

    console.log("isTransactionProcessable receipt", receipt);

    const syncedSnippet = await destCrossChainSyncContract.read.getSyncedSnippet([BigInt(0)]);
    const blockHash = syncedSnippet["blockHash"];
    console.log("isTransactionProcessable syncedSnippet", srcChainId, destChainId, syncedSnippet, syncedSnippet["blockHash"]);

    const srcBlock = await publicClient({ chainId: Number(srcChainId) }).getBlock({
      blockHash,
    });

    console.log("isTransactionProcessable srcBlock", srcBlock)

    return srcBlock.number !== null && receipt.blockNumber <= srcBlock.number;
  } catch (error) {
    console.log("isTransactionProcessable error", srcChainId, destChainId, error);
    return false;
  }
}
