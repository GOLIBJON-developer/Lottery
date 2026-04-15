import { formatEther } from 'viem'
import { fmtAddr, ZERO } from '@/lib/utils'
import { StatRow } from '@/components/ui/StatRow'

interface Props {
  address: string
  hasEntered: boolean
  winnings: bigint
  refundAmt: bigint
}

export function UserStatus({ address, hasEntered, winnings, refundAmt }: Props) {
  return (
    <div className="glass" style={{ padding:'20px 24px' }}>
      <div style={{ fontSize:'0.7rem', color:'var(--text-muted)', fontFamily:'var(--font-display)', letterSpacing:'0.1em', marginBottom:14 }}>
        MY STATUS
      </div>
      <div style={{ display:'flex', flexDirection:'column', gap:10 }}>
        <StatRow label="Address" value={fmtAddr(address)} />
        <StatRow
          label="Entered"
          value={hasEntered ? '✓ Yes' : '✗ No'}
          color={hasEntered ? '#10b981' : 'var(--text-muted)'}
        />
        {winnings > ZERO && (
          <StatRow
            label="Winnings"
            value={`${parseFloat(formatEther(winnings)).toFixed(4)} ETH`}
            color="var(--neon-gold)"
          />
        )}
        {refundAmt > ZERO && (
          <StatRow
            label="Refund"
            value={`${parseFloat(formatEther(refundAmt)).toFixed(4)} ETH`}
            color="#f59e0b"
          />
        )}
      </div>
    </div>
  )
}
