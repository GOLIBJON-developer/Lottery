interface StatRowProps {
  label: string
  value: string
  color?: string
  href?: string
}

export function StatRow({ label, value, color, href }: StatRowProps) {
  return (
    <div style={{ display:'flex', justifyContent:'space-between', alignItems:'center', fontSize:'0.8rem' }}>
      <span style={{ color:'var(--text-muted)' }}>{label}</span>
      {href ? (
        <a href={href} target="_blank" rel="noopener noreferrer"
          style={{ fontFamily:'var(--font-display)', fontSize:'0.7rem', color:'var(--neon-cyan)', textDecoration:'none' }}>
          {value} ↗
        </a>
      ) : (
        <span style={{ fontFamily:'var(--font-display)', fontSize:'0.75rem', color: color || 'inherit' }}>
          {value}
        </span>
      )}
    </div>
  )
}
