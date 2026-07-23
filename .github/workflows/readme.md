─────────────────────────────────────────────────────────────
CI to'g'ridan K8s   yo'q (SSH)     HA (helm)      YO'Q (git push) 
Rollback            docker run     helm rollback  git revert
Audit trail         yo'q           helm history   git log (to'liq)
Murakkablik         past           o'rta           yuqori
Portfolio uchun     ✓ asosiy       ✓✓ kuchli       ✓✓✓ eng kuchli

GitHub Secrets — kerakli ro'yxat
AWS_ROLE_ARN                          → OIDC auth (barcha strategiyalar)
EC2_SSH_PRIVATE_KEY                   → EC2+Ansible uchun
GITOPS_TOKEN                          → ArgoCD strategiyasi uchun
NEXT_PUBLIC_SEPOLIA_RPC_URL           → Docker build uchun
NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID → Docker build uchun
------------------------------------------------------------------
# CD



### 1-Opsiya: Sof CLI orqali Sync qilish (Tavsiya etiladi ⭐️)

`self-hosted` runner K8s klasteringiz ichida joylashgani uchun external Action'larsiz, to'g'ridan-to'g'ri CLI orqali tezkor va sodda sync qilish usuli:

```yaml
  cd:
    needs: ci
    runs-on: self-hosted
    steps:
      # 1. ArgoCD CLI yuklab olish (Agar runner'ingizda oldindan o'rnatilmagan bo'lsa)
      - name: Install ArgoCD CLI
        run: |
          if ! command -v argocd &> /dev/null; then
            echo "ArgoCD CLI topilmadi, o'rnatilmoqda..."
            curl -sSL -o /tmp/argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
            sudo install -m 555 /tmp/argocd-linux-amd64 /usr/local/bin/argocd
            rm /tmp/argocd-linux-amd64
          fi

      # 2. ArgoCD Login va App Sync
      - name: ArgoCD Sync Application
        run: |
          # ArgoCD serverining K8s ichki servisiga ulanamiz
          argocd login argocd-server.argocd.svc.cluster.local:443 \
            --insecure \
            --grpc-web \
            --username "${{ secrets.ARGOCD_USERNAME }}" \
            --password "${{ secrets.ARGOCD_PASSWORD }}"

          # Ilovani sync qilamiz va uning Pruned/Healthy bo'lishini kutamiz
          argocd app sync raffle --async
          argocd app wait raffle --health

```

---

### 2-Opsiya: Tayyor `argocd-action` bilan qilish

Agar rasmiy Action'dan foydalanmoqchi bo'lsangiz, `run:` va `curl` buyruqlarini olib tashlab, faqat `with:` parametrlari bilan qoldirasiz:

```yaml
  cd:
    needs: ci
    runs-on: self-hosted
    steps:
      - name: ArgoCD App Sync
        uses: argoproj/argocd-action@v2
        with:
          address: "argocd-server.argocd.svc.cluster.local:443"
          argocd_username: ${{ secrets.ARGOCD_USERNAME }}
          argocd_password: ${{ secrets.ARGOCD_PASSWORD }}
          argocd_app_name: raffle
          flags: --insecure --grpc-web

```

---

## 💡 GitOps nuqtai nazaridan muhim eslatma!

Sizning `ci` job'ingiz `values.yaml` ni yangilab, repository'ga `git push` qiladi.

ArgoCD tabiatan **GitOps (Pull Model)** asosida ishlaydi — ya'ni u Git'dagi o'zgarishni ko'rib, avtomatik ravishda (Auto-Sync yoqilgan bo'lsa 3 daqiqa ichida) klasterni update qiladi.

`cd` job'idagi `argocd app sync` buyrug'ining asosiy foydasi — **kutmaysiz**, o'sha zahotiyoq ArgoCD'ga *"Hoziroq Git'dan yangi versiyani tortib, Pod'larni yangila!"* deb buyruq beradi.