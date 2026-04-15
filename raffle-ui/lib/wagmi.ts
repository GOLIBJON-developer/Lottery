'use client'
import { getDefaultConfig } from '@rainbow-me/rainbowkit'
import { sepolia } from 'wagmi/chains'

export const config = getDefaultConfig({
  appName: 'Raffle',
  projectId: 'YOUR_ID', // WalletConnect project ID (walletconnect.com)
  chains: [sepolia],
  ssr: true,
})
