 GitHub Actions da — .env fayl repo da EMAS
 - name: Docker build
   run: |
     docker build \
       --build-arg NEXT_PUBLIC_SEPOLIA_RPC_URL="${{ secrets.NEXT_PUBLIC_SEPOLIA_RPC_URL }}" \
       --build-arg NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID="${{ secrets.NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID }}" \
       -t $IMAGE_TAG \
       ./raffle-ui

# 1       DOCKER IMG BUILD QILISH CMD
```
 docker build   --build-arg NEXT_PUBLIC_SEPOLIA_RPC_URL="https://eth-sepolia.g.alchemy.com/v2/<API_KEY>"   --build-arg NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID="<WALLET_CONNECT_PROJECT_ID>"   -t golibjon/my-repo:1.0.0 .
 docker run -d --name raffle-ui -p 3000:3000 --restart always golibjon/my-repo:1.0.0

```
docker-compose.yml fayli:
```
version: '3.8'

services:
  raffle-ui:
    image: golibjon/my-repo:1.0.0
    container_name: raffle-ui
    restart: always
    ports:
      # Agar serveringizda Nginx/Caddy kabi Reverse Proxy bo'lsa: "127.0.0.1:3000:3000"
      # Agar portni to'g'ridan-to'g'ri tashqariga ochmoqchi bo'lsangiz: "3000:3000"
      - "3000:3000"
    
    # Server diski loglar bilan to'lib qolmasligi uchun chegara
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"

    # Server resurslarini (CPU/RAM) asrash uchun limitlar
    deploy:
      resources:
        limits:
          cpus: '0.50'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 256M
```