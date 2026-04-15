'use client'

interface ToastProps {
  msg: string
  type: 'success' | 'error' | 'info'
}

export function Toast({ msg, type }: ToastProps) {
  return <div className={`toast toast-${type}`}>{msg}</div>
}
