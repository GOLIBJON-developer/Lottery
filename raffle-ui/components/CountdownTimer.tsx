'use client'
import { useState, useEffect } from 'react'

interface Props {
  lastTimestamp: bigint
  interval: bigint
}

export function CountdownTimer({ lastTimestamp, interval }: Props) {
  const [remaining, setRemaining] = useState(0)

  useEffect(() => {
    const calc = () => {
      const end = Number(lastTimestamp) + Number(interval)
      const now = Math.floor(Date.now() / 1000)
      setRemaining(Math.max(0, end - now))
    }
    calc()
    const id = setInterval(calc, 1000)
    return () => clearInterval(id)
  }, [lastTimestamp, interval])

  const h = Math.floor(remaining / 3600)
  const m = Math.floor((remaining % 3600) / 60)
  const s = remaining % 60

  const pad = (n: number) => n.toString().padStart(2, '0')

  if (remaining === 0) return (
    <span style={{ color: '#10b981', fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: 'inherit' }}>
      DRAW READY
    </span>
  )

  return (
    <span style={{ fontFamily: 'var(--font-display)', fontWeight: 700, fontSize: 'inherit', letterSpacing: '0.05em' }}>
      {h > 0 ? `${pad(h)}:` : ''}{pad(m)}:{pad(s)}
    </span>
  )
}
