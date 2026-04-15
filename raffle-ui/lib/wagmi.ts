'use client'
import { getDefaultConfig } from '@rainbow-me/rainbowkit'
import { sepolia } from 'wagmi/chains'
import { http } from 'wagmi'

export const config = getDefaultConfig({
  appName: 'Raffle',
  projectId: process.env.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID, // WalletConnect project ID (walletconnect.com)
  chains: [sepolia],
  ssr: true,
  transports: {
    [sepolia.id]: http(process.env.NEXT_PUBLIC_SEPOLIA_RPC_URL),
  },
})
