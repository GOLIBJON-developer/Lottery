# 1-Bosqich: deps (O'zgarishsiz qoladi)
FROM node:20-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci

# 2-Bosqich: builder (O'zgarishsiz qoladi)
FROM node:20-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ARG NEXT_PUBLIC_SEPOLIA_RPC_URL
ARG NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID
ENV NEXT_PUBLIC_SEPOLIA_RPC_URL=$NEXT_PUBLIC_SEPOLIA_RPC_URL
ENV NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID=$NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID
ENV NEXT_TELEMETRY_DISABLED=1
RUN npm run build

# 3-Bosqich: runner (YENGILLASHTIRILGAN VARIANT)
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Agar public papkangiz bo'lsa, ushbu qatorni ochib qo'ying:
# COPY --from=builder /app/public ./public

# --- ENGI ASOSIY JOYLARI ---
# Next.js tomonidan tayyorlangan standalone paketni to'liq nusxalaymiz
COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

USER nextjs

EXPOSE 3000
ENV PORT=3000
ENV HOSTNAME="0.0.0.0"

# Diqqat: Endi "npm start" emas, to'g'ridan-to'g'ri mitti "server.js" ishga tushadi!
CMD ["node", "server.js"]