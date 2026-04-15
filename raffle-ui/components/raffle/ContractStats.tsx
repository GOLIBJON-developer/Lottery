import { StatRow } from '@/components/ui/StatRow'
import { fmtAddr } from '@/lib/utils'
import { RAFFLE_ADDRESS } from '@/lib/contract'

interface Props {
  totalRounds: number
  maxPlayers: bigint
  protocolBps: bigint
}

export function ContractStats({ totalRounds, maxPlayers, protocolBps }: Props) {
  return (
    <div className="glass" style={{ padding:'20px 24px' }}>
      <div style={{ fontSize:'0.7rem', color:'var(--text-muted)', fontFamily:'var(--font-display)', letterSpacing:'0.1em', marginBottom:14 }}>
        CONTRACT STATS
      </div>
      <div style={{ display:'flex', flexDirection:'column', gap:10 }}>
        <StatRow label="Total rounds"   value={totalRounds.toString()} />
        <StatRow label="Max players"    value={maxPlayers.toString()} />
        <StatRow label="Protocol fee"   value={`${Number(protocolBps) / 100}%`} />
        <StatRow label="Network"        value="Sepolia" />
        <StatRow
          label="Contract"
          value={`${fmtAddr(RAFFLE_ADDRESS)} ↗`}
          href={`https://sepolia.etherscan.io/address/${RAFFLE_ADDRESS}`}
        />
      </div>
    </div>
  )
}
