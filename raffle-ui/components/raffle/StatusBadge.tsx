import { STATE_LABELS, STATE_CLASSES } from '@/lib/utils'

interface Props {
  raffleState: number
  isPaused: boolean
  roundId: bigint
}

export function StatusBadge({ raffleState, isPaused, roundId }: Props) {
  return (
    <div style={{ display:'flex', justifyContent:'center', alignItems:'center', gap:12, marginBottom:12 }}>
      <div className={`badge ${isPaused ? 'badge-paused' : STATE_CLASSES[raffleState] ?? 'badge-open'}`}>
        <div className="dot-pulse" />
        {isPaused ? 'PAUSED' : STATE_LABELS[raffleState] ?? 'OPEN'}
      </div>
      <div style={{ color:'var(--text-muted)', fontSize:'0.75rem', fontFamily:'var(--font-display)' }}>
        ROUND #{roundId.toString()}
      </div>
    </div>
  )
}
