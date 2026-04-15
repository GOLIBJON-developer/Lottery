import { formatEther } from 'viem'

export const fmtAddr = (a: string) => `${a.slice(0,6)}...${a.slice(-4)}`

export const fmtEth  = (v: bigint, decimals = 4) =>
  parseFloat(formatEther(v)).toFixed(decimals)

export const ZERO = BigInt(0)

export const STATE_LABELS  = ['OPEN', 'CALCULATING', 'CANCELLED'] as const
export const STATE_CLASSES = ['badge-open', 'badge-calc', 'badge-cancelled'] as const
