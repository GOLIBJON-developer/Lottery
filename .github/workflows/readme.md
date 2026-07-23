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




----------------------------------------------------------------------------------------------------------------------
# ArgoCD da loyiha yo'q yoki o'chgan bo'lsa yaratish
----------------------------------------------------------------------------------------------------------------------

Bu GitOps'dagi **Declarative Infrastructure** (Infrastrukturani kod ko'rinishida tavsiflash) tushunchasining eng muhim joylaridan biri.

Sodda qilib aytganda: **Odatiy `argocd app sync` buyrug'i agar ilova ArgoCD'da yo'q bo'lsa, uni avtomatik yaratib berolmaydi** va workflow `Application 'raffle' does not exist` degan xatolik berib to'xtaydi.

Lekin Platform Engineer sifatida buni **100% avtomatlashtirishning va "yo'q bo'lsa o'zing yaratib ol" deydigan qilishning 2 xil professional usuli** bor:

---

## 1. Yechim: `kubectl apply` orqali Declarative Manifest ishlatish (Eng to'g'ri va GitOps usuli)

ArgoCD'dagi har bir loyiha (Application) Kubernetes'ning oddiy Custom Resource (CRD) obyekti hisoblanadi. Siz loyaltyingiz Git reposida `infra/argocd/application.yaml` faylini saqlaysiz.

### Step 1: Repoda `application.yaml` yaratish

Repository'ingizga `infra/argocd/application.yaml` faylini joylaysiz:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: raffle
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/GOLIBJON-developer/Lottery.git'
    targetRevision: HEAD
    path: 'infra/helmfiles' # values.yaml joylashgan papka
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: raffle
  syncPolicy:
    automated:
      prune: true
      selfHeal: true

```

### Step 2: CI/CD Pipeline'da uni Apply qilish

Pipeline'dagi `cd` job'ingizda ArgoCD CLI o'rniga oddiy `kubectl` orqali manifests'ni apply qilasiz:

```yaml
  cd:
    needs: ci
    runs-on: self-hosted
    steps:
      - name: Checkout Repository
        uses: actions/checkout@v4

      - name: Deploy or Sync ArgoCD Application
        run: |
          # 1. Agar App ArgoCD'da yo'q bo'lsa yaratadi, bor bo'lsa parametrlarini yangilaydi
          kubectl apply -f infra/argocd/application.yaml

          # 2. Keyin uni darhol Sync qiladi
          argocd app sync raffle-ui \
            --server argocd-server.argocd.svc.cluster.local:443 \
            --insecure \
            --auth-token "${{ secrets.ARGOCD_TOKEN }}"

```

> **Afzalligi:** Agar ArgoCD'dan `raffle-ui` tasodifan o'chib ketsa ham, CI/CD run bo'lganda `kubectl apply` uni **qaytadan noldan tiklab beradi**!

---

## 2. Yechim: ArgoCD CLI orqali "Bo'lmasa yarat, bor bo'lsa sync qil" skripti

Agar alohida YAML fayl yaratginingiz kelmasa, `cd` job'ingizdagi bash skriptga kichik mantiqiy shart (`if/else`) qo'shasiz:

```yaml
  cd:
    needs: ci
    runs-on: self-hosted
    steps:
      - name: Ensure ArgoCD App exists and Sync
        run: |
          ARGOCD_SERVER="argocd-server.argocd.svc.cluster.local:443"
          
          # Login qilish
          argocd login $ARGOCD_SERVER \
            --insecure \
            --username "${{ secrets.ARGOCD_USERNAME }}" \
            --password "${{ secrets.ARGOCD_PASSWORD }}"

          # App bor-yo'qligini tekshiramiz
          if ! argocd app get raffle > /dev/null 2>&1; then
            echo "⚠️ 'raffle' topilmadi. Yangi Application yaratilmoqda..."
            
            argocd app create raffle \
              --repo https://github.com/GOLIBJON-developer/Lottery.git \
              --path infra/helmfiles \
              --dest-server https://kubernetes.default.svc \
              --dest-namespace default \
              --project default \
              --sync-policy automated
          else
            echo "✅ 'raffle' mavjud. Sync jarayoni boshlanmoqda..."
          fi

          # Baribir yakunda Sync buyrug'ini beramiz
          argocd app sync raffle

```

---

## 🎯 Qaysi birini tanlagan ma'qul?

**1-Yechim (`infra/argocd/application.yaml`)** eng to'g'ri va xavfsiz yo'l hisoblanadi. Nega deysizmi?
Chunki K8s va GitOps falsafasiga ko'ra, klasterdagi barcha obyektlar (shu jumladan ArgoCD Application'ning o'zi ham) **Git reponing ichida declarative (YAML) shaklda saqlanishi kerak**. Shunda klasteringiz kuyib ketgan taqdirda ham, bitta buyruq bilan butun arxitekturangizni qayta tiklab olasiz.