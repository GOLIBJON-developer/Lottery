'use client'
import { useState } from 'react'
import { parseEther, isAddress } from 'viem'
import { formatEther } from 'viem'
import { fmtAddr } from '@/lib/utils'
import { useRaffleWrite } from '@/hooks/useRaffleWrite'
import { Divider } from '@/components/ui/Divider'

interface Props {
  isPaused:      boolean
  raffleState:   number
  pendingClaims: bigint
  protocolBps:   bigint
  treasury:      string
  onRefetch:     () => void
  showToast:     (msg: string, type?: 'success'|'error'|'info') => void
}

export function OwnerPanel({ isPaused, raffleState, pendingClaims, protocolBps, treasury, onRefetch, showToast }: Props) {
  const [newFee,      setNewFee]      = useState('')
  const [newBps,      setNewBps]      = useState('')
  const [newTreasury, setNewTreasury] = useState('')

  const { send, isBusy } = useRaffleWrite(onRefetch, showToast)

  const canCancel = isPaused && raffleState === 0

  return (
    <div className="glass" style={{ padding:24, display:'flex', flexDirection:'column', gap:20 }}>

      {/* Header */}
      <div style={{ display:'flex', alignItems:'center', gap:8 }}>
        <div style={{ width:8, height:8, borderRadius:'50%', background:'#f59e0b', boxShadow:'0 0 8px #f59e0b' }} />
        <span style={{ fontSize:'0.7rem', fontFamily:'var(--font-display)', letterSpacing:'0.12em', color:'#f59e0b' }}>
          OWNER PANEL
        </span>
      </div>

      {/* Pause / Cancel */}
      <div style={{ display:'flex', gap:8 }}>
        <OwnerButton
          label={isPaused ? '▶ Unpause' : '⏸ Pause'}
          onClick={() => send(isPaused ? 'unpause' : 'pause')}
          disabled={isBusy}
          color={isPaused ? 'green' : 'red'}
        />
        <OwnerButton
          label="✕ Cancel Round"
          onClick={() => send('cancelRaffle')}
          disabled={isBusy || !canCancel}
          color={canCancel ? 'red' : 'muted'}
          title={!canCancel ? 'Must be paused + OPEN state' : undefined}
        />
      </div>

      <Divider />

      {/* Entrance fee */}
      <OwnerField
        label={`SET ENTRANCE FEE (ETH)`}
        placeholder="e.g. 0.01"
        value={newFee}
        onChange={setNewFee}
        onSubmit={() => {
          if (!newFee || isNaN(+newFee)) return showToast('Invalid fee', 'error')
          send('setEntranceFee', [parseEther(newFee)])
          setNewFee('')
        }}
        disabled={isBusy || !isPaused}
        warning={!isPaused ? '⚠ Pause first' : undefined}
      />

      {/* Protocol fee */}
      <OwnerField
        label={`SET PROTOCOL FEE (BPS) — current: ${protocolBps.toString()} (${Number(protocolBps)/100}%)`}
        placeholder="e.g. 200 = 2%"
        value={newBps}
        onChange={setNewBps}
        onSubmit={() => {
          const v = parseInt(newBps)
          if (isNaN(v) || v < 0 || v > 1000) return showToast('BPS must be 0–1000', 'error')
          send('setProtocolFee', [BigInt(v)])
          setNewBps('')
        }}
        disabled={isBusy || !isPaused}
      />

      {/* Treasury */}
      <OwnerField
        label={`SET TREASURY — current: ${treasury ? fmtAddr(treasury) : '—'}`}
        placeholder="0x..."
        value={newTreasury}
        onChange={setNewTreasury}
        onSubmit={() => {
          if (!isAddress(newTreasury)) return showToast('Invalid address', 'error')
          send('setTreasury', [newTreasury])
          setNewTreasury('')
        }}
        disabled={isBusy || !isPaused}
      />

      <Divider />

      {/* Emergency withdraw */}
      <div>
        <div style={{ fontSize:'0.65rem', color:'var(--text-muted)', fontFamily:'var(--font-display)', letterSpacing:'0.08em', marginBottom:8 }}>
          EMERGENCY WITHDRAW — orphaned ETH only
        </div>
        <OwnerButton
          label="⚠ Emergency Withdraw"
          onClick={() => send('emergencyWithdraw')}
          disabled={isBusy || !isPaused}
          color={isPaused ? 'red' : 'muted'}
          fullWidth
        />
        <div style={{ fontSize:'0.6rem', color:'var(--text-muted)', marginTop:4 }}>
          Protected (pending claims): {parseFloat(formatEther(pendingClaims)).toFixed(4)} ETH
        </div>
      </div>

      {isBusy && (
        <div style={{ display:'flex', alignItems:'center', gap:8, fontSize:'0.75rem', color:'var(--text-muted)' }}>
          <div className="spinner" style={{ width:14, height:14 }} />
          Waiting for confirmation...
        </div>
      )}
    </div>
  )
}

/* ── Reusable sub-components ─────────────────────────────────── */

type BtnColor = 'green' | 'red' | 'purple' | 'muted'

const COLOR_MAP: Record<BtnColor, { bg: string; border: string; color: string }> = {
  green:  { bg:'rgba(16,185,129,0.15)',  border:'rgba(16,185,129,0.3)',  color:'#10b981' },
  red:    { bg:'rgba(239,68,68,0.12)',   border:'rgba(239,68,68,0.3)',   color:'#ef4444' },
  purple: { bg:'rgba(168,85,247,0.12)',  border:'rgba(168,85,247,0.3)',  color:'#a855f7' },
  muted:  { bg:'rgba(255,255,255,0.03)', border:'rgba(255,255,255,0.08)',color:'var(--text-muted)' },
}

function OwnerButton({ label, onClick, disabled, color = 'purple', fullWidth, title }: {
  label: string; onClick: () => void; disabled?: boolean
  color?: BtnColor; fullWidth?: boolean; title?: string
}) {
  const c = COLOR_MAP[color]
  return (
    <button
      className="btn-owner"
      style={{ ...(fullWidth && { width:'100%' }), background:c.bg, borderColor:c.border, color:c.color,
        cursor: disabled ? 'not-allowed' : 'pointer' }}
      onClick={onClick}
      disabled={disabled}
      title={title}
    >
      {label}
    </button>
  )
}

function OwnerField({ label, placeholder, value, onChange, onSubmit, disabled, warning }: {
  label: string; placeholder: string; value: string
  onChange: (v: string) => void; onSubmit: () => void
  disabled?: boolean; warning?: string
}) {
  return (
    <div>
      <div style={{ fontSize:'0.65rem', color:'var(--text-muted)', fontFamily:'var(--font-display)', letterSpacing:'0.08em', marginBottom:8 }}>
        {label}
      </div>
      <div style={{ display:'flex', gap:8 }}>
        <input
          className="owner-input"
          placeholder={placeholder}
          value={value}
          onChange={e => onChange(e.target.value)}
          onKeyDown={e => e.key === 'Enter' && !disabled && onSubmit()}
        />
        <OwnerButton label="Set" onClick={onSubmit} disabled={disabled} color="purple" />
      </div>
      {warning && <div style={{ fontSize:'0.6rem', color:'#f59e0b', marginTop:4 }}>{warning}</div>}
    </div>
  )
}
