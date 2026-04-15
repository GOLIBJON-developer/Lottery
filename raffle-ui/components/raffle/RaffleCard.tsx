'use client'
import { formatEther } from 'viem'
import { useEffect } from 'react'
import { useWriteContract, useWaitForTransactionReceipt } from 'wagmi'
import { RAFFLE_ADDRESS, RAFFLE_ABI } from '@/lib/contract'
import { ZERO } from '@/lib/utils'
import { StatusBadge } from './StatusBadge'
import { CountdownTimer } from '@/components/CountdownTimer'
import { Divider } from '@/components/ui/Divider'

interface Props {
  raffleState:  number
  isPaused:     boolean
  roundId:      bigint
  roundPot:     bigint
  playerCount:  bigint
  maxPlayers:   bigint
  lastTs:       bigint
  interval:     bigint
  entranceFee:  bigint
  isConnected:  boolean
  hasEntered:   boolean
  winnings:     bigint
  refundAmt:    bigint
  onSuccess:    () => void
  showToast:    (msg: string, type?: 'success'|'error'|'info') => void
}

export function RaffleCard({
  raffleState, isPaused, roundId, roundPot, playerCount, maxPlayers,
  lastTs, interval, entranceFee, isConnected, hasEntered,
  winnings, refundAmt, onSuccess, showToast,
}: Props) {
  const fillPct = maxPlayers > ZERO ? Number((playerCount * BigInt(100)) / maxPlayers) : 0

  /* ── Enter ─────────────────────────────────────────────────── */
  const { writeContract: enterWrite, data: enterHash, isPending: enterPending } = useWriteContract()
  const { isLoading: enterConfirming, isSuccess: enterSuccess } = useWaitForTransactionReceipt({ hash: enterHash })
  useEffect(() => { if (enterSuccess) { showToast('🎉 You entered!', 'success'); onSuccess() } }, [enterSuccess]) // eslint-disable-line

  /* ── Claim winnings ─────────────────────────────────────────── */
  const { writeContract: claimWrite, data: claimHash, isPending: claimPending } = useWriteContract()
  const { isSuccess: claimSuccess } = useWaitForTransactionReceipt({ hash: claimHash })
  useEffect(() => { if (claimSuccess) { showToast('💰 Prize claimed!', 'success'); onSuccess() } }, [claimSuccess]) // eslint-disable-line

  /* ── Claim refund ───────────────────────────────────────────── */
  const { writeContract: refundWrite, data: refundHash, isPending: refundPending } = useWriteContract()
  const { isSuccess: refundSuccess } = useWaitForTransactionReceipt({ hash: refundHash })
  useEffect(() => { if (refundSuccess) { showToast('↩️ Refund claimed!', 'success'); onSuccess() } }, [refundSuccess]) // eslint-disable-line

  const isBusy   = enterPending || enterConfirming
  const canEnter = isConnected && raffleState === 0 && !isPaused && !hasEntered && !isBusy

  return (
    <div className="glass" style={{ padding:'clamp(20px,4vw,36px)', display:'flex', flexDirection:'column', gap:24 }}>

      {/* Status */}
      <div style={{ textAlign:'center' }}>
        <StatusBadge raffleState={raffleState} isPaused={isPaused} roundId={roundId} />
        <h1 className="title-raffle">RAFFLE</h1>
      </div>

      {/* Prize pot */}
      <div style={{
        textAlign:'center', padding:20, borderRadius:16,
        background:'linear-gradient(135deg,rgba(168,85,247,0.08),rgba(0,245,255,0.06))',
        border:'1px solid rgba(168,85,247,0.2)',
      }}>
        <div style={{ fontSize:'0.75rem', color:'var(--text-muted)', letterSpacing:'0.1em', marginBottom:6, fontFamily:'var(--font-display)' }}>
          PRIZE POT
        </div>
        <div className="stat-value" style={{
          fontSize:'clamp(2rem,5vw,3rem)',
          background:'linear-gradient(135deg,#fff,#f59e0b)',
          WebkitBackgroundClip:'text', WebkitTextFillColor:'transparent', backgroundClip:'text',
          filter:'drop-shadow(0 0 12px rgba(245,158,11,0.4))',
        }}>
          {parseFloat(formatEther(roundPot)).toFixed(4)} ETH
        </div>
        <div style={{ fontSize:'0.75rem', color:'var(--text-muted)', marginTop:4 }}>
          ≈ ${(parseFloat(formatEther(roundPot)) * 2500).toFixed(0)}
        </div>
      </div>

      {/* Players + Countdown */}
      <div style={{ display:'grid', gridTemplateColumns:'1fr 1px 1fr', alignItems:'center' }}>
        <div style={{ textAlign:'center', padding:'0 16px' }}>
          <div style={{ fontSize:'0.7rem', color:'var(--text-muted)', fontFamily:'var(--font-display)', letterSpacing:'0.08em', marginBottom:4 }}>
            PLAYERS
          </div>
          <div className="stat-value" style={{ fontSize:'clamp(1.4rem,3vw,1.8rem)' }}>
            {playerCount.toString()}
            <span style={{ color:'var(--text-muted)', fontSize:'0.9em' }}>/{maxPlayers.toString()}</span>
          </div>
          <div className="progress-track" style={{ marginTop:8 }}>
            <div className="progress-fill" style={{ width:`${fillPct}%` }} />
          </div>
        </div>
        <div style={{ height:40, background:'var(--glass-border)' }} />
        <div style={{ textAlign:'center', padding:'0 16px' }}>
          <div style={{ fontSize:'0.7rem', color:'var(--text-muted)', fontFamily:'var(--font-display)', letterSpacing:'0.08em', marginBottom:4 }}>
            DRAW IN
          </div>
          <div style={{ fontSize:'clamp(1.2rem,2.5vw,1.6rem)' }}>
            {lastTs > ZERO ? <CountdownTimer lastTimestamp={lastTs} interval={interval} /> : '—'}
          </div>
        </div>
      </div>

      <Divider />

      {/* Enter button */}
      <EnterButton
        canEnter={canEnter}
        isBusy={isBusy}
        hasEntered={hasEntered}
        raffleState={raffleState}
        isPaused={isPaused}
        isConnected={isConnected}
        entranceFee={entranceFee}
        onEnter={() => enterWrite({ address:RAFFLE_ADDRESS, abi:RAFFLE_ABI, functionName:'enterRaffle', value:entranceFee })}
      />

      {/* Claim buttons */}
      {(winnings > ZERO || refundAmt > ZERO) && (
        <div style={{ display:'flex', gap:10 }}>
          {winnings > ZERO && (
            <ClaimButton
              label="CLAIM PRIZE"
              amount={winnings}
              onClick={() => claimWrite({ address:RAFFLE_ADDRESS, abi:RAFFLE_ABI, functionName:'claimWinnings' })}
              disabled={claimPending}
            />
          )}
          {refundAmt > ZERO && (
            <ClaimButton
              label="CLAIM REFUND"
              amount={refundAmt}
              onClick={() => refundWrite({ address:RAFFLE_ADDRESS, abi:RAFFLE_ABI, functionName:'claimRefund' })}
              disabled={refundPending}
            />
          )}
        </div>
      )}

      {/* Fee row */}
      <div style={{
        display:'flex', justifyContent:'space-between', alignItems:'center',
        padding:'10px 14px', borderRadius:10,
        background:'rgba(255,255,255,0.02)', border:'1px solid rgba(255,255,255,0.06)',
        fontSize:'0.75rem',
      }}>
        <span style={{ color:'var(--text-muted)' }}>Entrance fee</span>
        <span style={{ fontFamily:'var(--font-display)', color:'var(--neon-gold)' }}>
          {formatEther(entranceFee)} ETH
        </span>
      </div>
    </div>
  )
}

/* ── Sub-components ─────────────────────────────────────────── */

function EnterButton({ canEnter, isBusy, hasEntered, raffleState, isPaused, isConnected, entranceFee, onEnter }: {
  canEnter: boolean; isBusy: boolean; hasEntered: boolean
  raffleState: number; isPaused: boolean; isConnected: boolean
  entranceFee: bigint; onEnter: () => void
}) {
  const label = isBusy      ? <><div className="spinner" /> CONFIRMING...</>
    : hasEntered             ? <><span>✓</span> ALREADY ENTERED</>
    : raffleState !== 0      ? <><span>⏳</span> DRAW IN PROGRESS</>
    : isPaused               ? <><span>⏸</span> RAFFLE PAUSED</>
    : !isConnected           ? <>CONNECT WALLET</>
    : <>ENTER — {formatEther(entranceFee)} ETH</>

  return (
    <button className="btn-holo w-full" onClick={onEnter} disabled={!canEnter}>
      <div className="btn-holo-inner">{label}</div>
    </button>
  )
}

function ClaimButton({ label, amount, onClick, disabled }: {
  label: string; amount: bigint; onClick: () => void; disabled: boolean
}) {
  return (
    <button className="btn-holo" style={{ flex:1 }} onClick={onClick} disabled={disabled}>
      <div className="btn-holo-inner" style={{ padding:'14px 20px', flexDirection:'column', gap:2 }}>
        <span style={{ fontSize:'0.65rem', opacity:0.7 }}>{label}</span>
        <span>{parseFloat(formatEther(amount)).toFixed(4)} ETH</span>
      </div>
    </button>
  )
}
