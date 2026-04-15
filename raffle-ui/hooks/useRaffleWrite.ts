import { useEffect } from 'react'
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { RAFFLE_ADDRESS, RAFFLE_ABI } from '@/lib/contract'

type ToastFn = (msg: string, type?: 'success' | 'error' | 'info') => void

export function useRaffleWrite(onSuccess?: () => void, toast?: ToastFn) {
  const { writeContract, data: hash, isPending, error } = useWriteContract()
  const { isLoading: isConfirming, isSuccess } = useWaitForTransactionReceipt({ hash })

  useEffect(() => {
    if (isSuccess) { toast?.('Transaction confirmed ✓', 'success'); onSuccess?.() }
    if (error)     { toast?.('Transaction failed', 'error') }
  }, [isSuccess, error]) // eslint-disable-line react-hooks/exhaustive-deps

  const send = (functionName: string, args?: unknown[], value?: bigint) => {
    const params: any = { address: RAFFLE_ADDRESS, abi: RAFFLE_ABI, functionName }
    if (args  !== undefined) params.args  = args
    if (value !== undefined) params.value = value
    writeContract(params)
  }

  return { send, isPending, isConfirming, isBusy: isPending || isConfirming, isSuccess }
}
