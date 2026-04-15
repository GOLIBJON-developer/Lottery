import { useAccount, useReadContract, useReadContracts } from 'wagmi'
import { RAFFLE_ADDRESS, RAFFLE_ABI } from '@/lib/contract'
import { ZERO } from '@/lib/utils'

const BATCH = [
  'getRaffleState', 'getEntranceFee',  'getCurrentRoundPot', 'getNumberOfPlayers',
  'getLastTimeStamp', 'getInterval',   'getRecentWinner',    'getWinnerHistory',
  'getCurrentRoundId','MAX_PLAYERS',   'isPaused',           'owner',
  'getPendingClaims', 'getProtocolFeeBps', 'getTreasury',
] as const

export function useRaffleData() {
  const { address } = useAccount()

  const { data, refetch, isLoading } = useReadContracts({
    contracts: BATCH.map(fn => ({ address: RAFFLE_ADDRESS, abi: RAFFLE_ABI, functionName: fn })),
    query: { refetchInterval: 12_000 },
  })

  const { data: hasEntered,  refetch: refetchUser } = useReadContract({
    address: RAFFLE_ADDRESS, abi: RAFFLE_ABI, functionName: 'hasEntered',
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 12_000 },
  })
  const { data: winnings } = useReadContract({
    address: RAFFLE_ADDRESS, abi: RAFFLE_ABI, functionName: 'getWinnings',
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 12_000 },
  })
  const { data: refundAmt } = useReadContract({
    address: RAFFLE_ADDRESS, abi: RAFFLE_ABI, functionName: 'getRefund',
    args: address ? [address] : undefined,
    query: { enabled: !!address, refetchInterval: 12_000 },
  })

  const r = (i: number) => data?.[i]?.result

  return {
    isLoading,
    refetch: () => { refetch(); refetchUser() },
    // contract state
    raffleState:   (r(0)  as number  ?? 0),
    entranceFee:   (r(1)  as bigint  ?? ZERO),
    roundPot:      (r(2)  as bigint  ?? ZERO),
    playerCount:   (r(3)  as bigint  ?? ZERO),
    lastTs:        (r(4)  as bigint  ?? ZERO),
    interval:      (r(5)  as bigint  ?? BigInt(3600)),
    recentWinner:  (r(6)  as string  ?? ''),
    winnerHistory: (r(7)  as string[] ?? []),
    roundId:       (r(8)  as bigint  ?? BigInt(1)),
    maxPlayers:    (r(9)  as bigint  ?? BigInt(500)),
    isPaused:      (r(10) as boolean ?? false),
    ownerAddr:     (r(11) as string  ?? ''),
    pendingClaims: (r(12) as bigint  ?? ZERO),
    protocolBps:   (r(13) as bigint  ?? ZERO),
    treasury:      (r(14) as string  ?? ''),
    // per-user
    hasEntered:    (hasEntered as boolean ?? false),
    winnings:      (winnings  as bigint  ?? ZERO),
    refundAmt:     (refundAmt as bigint  ?? ZERO),
  }
}
