'use client'
import { useState, useCallback, useEffect } from 'react'
import { useAccount } from 'wagmi'
import { useWatchContractEvent } from 'wagmi'
import { formatEther } from 'viem'
import { ConnectButton } from '@rainbow-me/rainbowkit'

import { RAFFLE_ADDRESS, RAFFLE_ABI } from '@/lib/contract'
import { fmtAddr } from '@/lib/utils'
import { useRaffleData } from '@/hooks/useRaffleData'

import { Toast }         from '@/components/ui/Toast'
import { RaffleCard }    from '@/components/raffle/RaffleCard'
import { OwnerPanel }    from '@/components/raffle/OwnerPanel'
import { WinnersList }   from '@/components/raffle/WinnersList'
import { ContractStats } from '@/components/raffle/ContractStats'
import { UserStatus }    from '@/components/raffle/UserStatus'

export function RaffleApp() {
  const { address, isConnected } = useAccount()
  const data = useRaffleData()

  const [toast, setToast] = useState<{ msg: string; type: 'success'|'error'|'info' }|null>(null)
  const [liveWinners, setLiveWinners] = useState<Array<{ address: string; prize: string; live: boolean }>>([])

  const showToast = useCallback((msg: string, type: 'success'|'error'|'info' = 'info') => {
    setToast({ msg, type })
    setTimeout(() => setToast(null), 4000)
  }, [])

  const isOwner = !!(address && data.ownerAddr && address.toLowerCase() === data.ownerAddr.toLowerCase())

  /* ── Live events ─────────────────────────────────────────── */
  useWatchContractEvent({
    address: RAFFLE_ADDRESS, abi: RAFFLE_ABI, eventName: 'WinnerPicked',
    onLogs(logs) {
      logs.forEach((log: any) => {
        const winner = log.args?.winner as string
        const prize  = log.args?.prize  as bigint
        if (!winner || !prize) return
        setLiveWinners(p => [{ address: winner, prize: formatEther(prize), live: true }, ...p].slice(0, 5))
        showToast(`🏆 Winner: ${fmtAddr(winner)} — ${formatEther(prize)} ETH`, 'success')
        data.refetch()
      })
    }
  })
  useWatchContractEvent({
    address: RAFFLE_ADDRESS, abi: RAFFLE_ABI, eventName: 'RaffleEnter',
    onLogs() { data.refetch() }
  })

  /* ── Merge live + history for display ────────────────────── */
  const displayWinners = [
    ...liveWinners,
    ...data.winnerHistory.slice().reverse().slice(0, 8).map(a => ({ address: a, prize: null as any, live: false })),
  ].slice(0, 8)

  return (
    <>
      {/* Background */}
      <div className="bg-space" /><div className="bg-stars" />
      <div className="bg-orb-1" /><div className="bg-orb-2" /><div className="bg-orb-3" />

      <div style={{
        position:'relative', zIndex:1, minHeight:'100vh',
        display:'flex', flexDirection:'column', alignItems:'center',
        padding:'clamp(16px,4vw,40px)', gap:24,
      }}>

        {/* ── Header ─────────────────────────────────────────── */}
        <header className="glass" style={{
          width:'100%', maxWidth:1100,
          display:'flex', alignItems:'center', justifyContent:'space-between',
          padding:'12px 20px',
        }}>
          <div style={{ display:'flex', alignItems:'center', gap:12 }}>
            <Logo />
            {isOwner && <OwnerBadge />}
          </div>
          <div style={{ display:'flex', alignItems:'center', gap:12 }}>
            <NetworkBadge />
            <ConnectButton accountStatus="avatar" chainStatus="none" showBalance={false} />
          </div>
        </header>

        {/* ── Grid ───────────────────────────────────────────── */}
        <main style={{
          width:'100%', maxWidth:1100,
          display:'grid',
          gridTemplateColumns: isOwner ? '1fr 1fr 1fr' : '1.4fr 1fr',
          gap:20,
        }}>

          {/* Col 1 — Raffle card */}
          <RaffleCard
            raffleState={data.raffleState}
            isPaused={data.isPaused}
            roundId={data.roundId}
            roundPot={data.roundPot}
            playerCount={data.playerCount}
            maxPlayers={data.maxPlayers}
            lastTs={data.lastTs}
            interval={data.interval}
            entranceFee={data.entranceFee}
            isConnected={isConnected}
            hasEntered={data.hasEntered}
            winnings={data.winnings}
            refundAmt={data.refundAmt}
            onSuccess={data.refetch}
            showToast={showToast}
          />

          {/* Col 2 — Info */}
          <div style={{ display:'flex', flexDirection:'column', gap:20 }}>
            {isConnected && address && (
              <UserStatus
                address={address}
                hasEntered={data.hasEntered}
                winnings={data.winnings}
                refundAmt={data.refundAmt}
              />
            )}
            <ContractStats
              totalRounds={data.winnerHistory.length}
              maxPlayers={data.maxPlayers}
              protocolBps={data.protocolBps}
            />
            <WinnersList
              winners={displayWinners}
              currentAddress={address}
              totalCount={data.winnerHistory.length}
            />
          </div>

          {/* Col 3 — Owner panel (only for owner) */}
          {isOwner && (
            <OwnerPanel
              isPaused={data.isPaused}
              raffleState={data.raffleState}
              pendingClaims={data.pendingClaims}
              protocolBps={data.protocolBps}
              treasury={data.treasury}
              onRefetch={data.refetch}
              showToast={showToast}
            />
          )}
        </main>

        <footer style={{ display:'flex', alignItems:'center', gap:8, opacity:0.5, fontSize:'0.7rem' }}>
          <span style={{ fontFamily:'var(--font-display)', letterSpacing:'0.08em' }}>
            ⚡ Powered by Chainlink VRF v2.5
          </span>
        </footer>
      </div>

      {toast && <Toast msg={toast.msg} type={toast.type} />}

      {/* Global owner styles (used across OwnerPanel) */}
      <style>{`
        .btn-owner {
          padding: 10px 16px; border-radius: 10px; cursor: pointer;
          border: 1px solid rgba(255,255,255,0.1);
          background: rgba(255,255,255,0.04);
          color: var(--text-primary);
          font-size: 0.78rem; font-family: var(--font-display);
          letter-spacing: 0.06em; white-space: nowrap;
          transition: filter 0.2s; flex: 1;
        }
        .btn-owner:hover:not(:disabled) { filter: brightness(1.2); }
        .btn-owner:disabled { opacity: 0.4; cursor: not-allowed; }
        .owner-input {
          flex: 1; min-width: 0;
          background: rgba(255,255,255,0.04);
          border: 1px solid rgba(255,255,255,0.1);
          border-radius: 10px; padding: 10px 14px;
          color: var(--text-primary);
          font-size: 0.82rem; font-family: var(--font-display);
          outline: none; transition: border-color 0.2s;
        }
        .owner-input:focus   { border-color: rgba(168,85,247,0.5); }
        .owner-input::placeholder { color: var(--text-muted); }
        @media (max-width: 900px) {
          main { grid-template-columns: 1fr !important; }
        }
      `}</style>
    </>
  )
}

/* ── Small header atoms ──────────────────────────────────────── */
function Logo() {
  return (
    <>
      <div style={{
        width:36, height:36, borderRadius:10,
        background:'linear-gradient(135deg,#a855f7,#00f5ff)',
        display:'flex', alignItems:'center', justifyContent:'center',
        fontSize:'1.2rem', fontWeight:900, fontFamily:'var(--font-display)',
        boxShadow:'0 0 16px rgba(168,85,247,0.5)',
      }}>⚡</div>
      <span style={{ fontFamily:'var(--font-display)', fontWeight:700, fontSize:'0.9rem', letterSpacing:'0.1em' }}>
        RAFFLE
      </span>
    </>
  )
}

function OwnerBadge() {
  return (
    <div style={{
      padding:'3px 10px', borderRadius:100,
      background:'rgba(245,158,11,0.15)', border:'1px solid rgba(245,158,11,0.3)',
      fontSize:'0.6rem', fontFamily:'var(--font-display)', color:'#f59e0b', letterSpacing:'0.08em',
    }}>
      OWNER
    </div>
  )
}

function NetworkBadge() {
  return (
    <div style={{
      display:'flex', alignItems:'center', gap:6,
      padding:'4px 10px', borderRadius:8,
      background:'rgba(0,245,255,0.08)', border:'1px solid rgba(0,245,255,0.2)',
    }}>
      <div style={{ width:6, height:6, borderRadius:'50%', background:'#00f5ff' }} className="dot-pulse" />
      <span style={{ fontSize:'0.65rem', fontFamily:'var(--font-display)', color:'#00f5ff', letterSpacing:'0.08em' }}>
        SEPOLIA
      </span>
    </div>
  )
}
