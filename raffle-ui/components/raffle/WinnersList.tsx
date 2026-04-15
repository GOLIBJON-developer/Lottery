import { fmtAddr } from '@/lib/utils'

interface Winner {
  address: string
  prize: string | null
  live?: boolean
}

interface Props {
  winners: Winner[]
  currentAddress?: string
  totalCount: number
}

export function WinnersList({ winners, currentAddress, totalCount }: Props) {
  return (
    <div className="glass" style={{ padding:'20px 24px', flex:1 }}>
      <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', marginBottom:14 }}>
        <div style={{ fontSize:'0.7rem', color:'var(--text-muted)', fontFamily:'var(--font-display)', letterSpacing:'0.1em' }}>
          RECENT WINNERS
        </div>
        {totalCount > 0 && (
          <div style={{ fontSize:'0.65rem', color:'var(--text-muted)' }}>{totalCount} total</div>
        )}
      </div>

      <div style={{ display:'flex', flexDirection:'column', gap:6, maxHeight:280, overflowY:'auto' }}>
        {winners.length === 0 ? (
          <div style={{ textAlign:'center', color:'var(--text-muted)', fontSize:'0.8rem', padding:'20px 0' }}>
            No winners yet
          </div>
        ) : winners.map((w, i) => (
          <WinnerRow key={i} winner={w} isYou={w.address.toLowerCase() === currentAddress?.toLowerCase()} />
        ))}
      </div>
    </div>
  )
}

function WinnerRow({ winner, isYou }: { winner: Winner; isYou: boolean }) {
  const hue = parseInt(winner.address.slice(2, 8), 16) % 360
  return (
    <div className={`winner-row ${isYou ? 'is-you' : ''}`}>
      <div style={{ display:'flex', alignItems:'center', gap:8 }}>
        <div style={{ width:28, height:28, borderRadius:8, flexShrink:0, background:`hsl(${hue},60%,55%)`, opacity:0.8 }} />
        <div>
          <div style={{ fontSize:'0.75rem', fontFamily:'var(--font-display)' }}>
            {fmtAddr(winner.address)}
            {isYou && <span style={{ marginLeft:6, fontSize:'0.6rem', color:'var(--neon-violet)' }}>YOU</span>}
          </div>
          {winner.live && <div style={{ fontSize:'0.6rem', color:'#10b981' }}>live</div>}
        </div>
      </div>
      {winner.prize && (
        <div style={{ fontSize:'0.75rem', fontFamily:'var(--font-display)', color:'var(--neon-gold)' }}>
          {parseFloat(winner.prize).toFixed(4)} ETH
        </div>
      )}
    </div>
  )
}
