
---

## 🔐 1. GitHub Secrets (Zaruriy Atrof-muhit O'zgaruvchilari)

Pipeline va ArgoCD integratsiyasi to'g'ri ishlashi uchun repozitoriyangizning **Settings ➔ Secrets and variables ➔ Actions** bo'limiga quyidagi kalitlarni qo'shib oling:

| Secret Nomi | Tavsifi |
| --- | --- |
| `ARGOCD_USERNAME` | ArgoCD tizimiga kirish logini (`admin`) |
| `ARGOCD_PASSWORD` | ArgoCD admin paroli |
| `DOCKERHUB_USERNAME` | DockerHub foydalanuvchi nomi |
| `DOCKERHUB_TOKEN` | DockerHub Access Token (yoki Parol) |
| `NEXT_PUBLIC_SEPOLIA_RPC_URL` | Web3 Sepolia RPC Node havolasi |
| `NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID` | WalletConnect Loyiha ID-si |

---

## 🚀 2. Infratuzilmani Bosqichma-Bosqich O'rnatish

1. **1-Qadam: Helm Utilitasini O'rnatish:** Ubuntu / Debian paket boshqaruvchisi orqali.
Tizimingizga rasmiy Helm APT repozitoriyasini qo'shib, o'rnatamiz:

```bash
HELM_BUILDKITE_APT_KEY_ID="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"

# Kerakli bog'liqliklarni o'rnatish
sudo apt-get update && sudo apt-get install curl gpg apt-transport-https --yes

# GPG kalitini yuklab olish va tekshirish
curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey > "${TMPDIR:-/tmp}/helm.gpg"

if [ "$(gpg --show-keys --with-colons "${TMPDIR:-/tmp}/helm.gpg" | awk -F: '$1 == "fpr" {print $10}' | head -n 1)" != "${HELM_BUILDKITE_APT_KEY_ID}" ]; then
  echo "ERROR: Unexpected Helm APT key ID: potential key compromise"
  exit 1
fi

# Repozitoriyani ulash hamda Helm'ni o'rnatish
cat "${TMPDIR:-/tmp}/helm.gpg" | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

sudo apt-get update
sudo apt-get install helm -y

```


2. **2-Qadam: ArgoCD Serverni Ishga Tushirish:** Helm Chart orqali K8s ichiga o'rnatish.
https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd

ArgoCD repozitoriyasini ulash:

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

```

Yengillashtirilgan va Ingress sozlangan `argocd.yaml` konfiguratsiya faylini yaratamiz:

```yaml
redis-ha:
  enabled: false

controller:
  replicas: 1

repoServer:
  replicas: 1

applicationSet:
  replicas: 1

global:
  domain: argocd.example.com

certificate:
  enabled: true

server:
  replicas: 1
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
      nginx.ingress.kubernetes.io/ssl-passthrough: "true"
      nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    tls: true

```

Klasterga joylash va mahalliy kirishni sozlash:

```bash
# ArgoCD chartini o'rnatish
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace -f argocd.yaml

# Local port-forwarding orqali bog'lanish
kubectl port-forward service/argocd-server -n argocd 8080:443

```

> **Lokal Domenni Birlashtirish:** `/etc/hosts` (Linux/Mac) yoki `C:\Windows\System32\drivers\etc\hosts` (Windows) fayliga quyidagi qatorni qo'shib qo'ying:
> `127.0.0.1 argocd.example.com`


3. **3-Qadam: Actions Runner Controller (ARC) O'rnatish:** Klaster ichida self-hosted runner ishlatish.
https://github.com/actions/actions-runner-controller  >  quickstart guide
1. **Cert-Manager o'rnatish:**

```bash
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml

```

2. **GitHub PAT (Personal Access Token) yaratish:**
GitHub `Developer Settings` ➔ `Personal access tokens` bo'limiga o'tib, **`repo`** huquqi bilan yangi PAT yaratib oling.
3. **ARC Operatorini Helm orqali o'rnatish:**

```bash
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
helm repo update

helm upgrade --install --namespace actions-runner-system --create-namespace \
  --set=authSecret.create=true \
  --set=authSecret.github_token="YOUR_GITHUB_PAT_TOKEN" \
  --wait actions-runner-controller actions-runner-controller/actions-runner-controller

```

note:- Replace REPLACE_YOUR_TOKEN_HERE with your PAT that was generated previously.

4. **Runner Deployment Manifestini qo'llash:**

```yaml
cat << EOF | kubectl apply -n actions-runner-system -f -
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: self-hosted-runners
spec:
  replicas: 1
  template:
    spec:
      repository: GOLIBJON-developer/Lottery
EOF

```

5. **Tekshirish:**

```bash
kubectl get runners -n actions-runner-system
kubectl get pods -n actions-runner-system

```


4. **4-Qadam: ArgoCD CLI Utilitasini O'rnatish:** Terminal orqali boshqarish uchun.
CLI binar faylini yuklab olib, tizim `PATH`iga o'tkazamiz:

```bash
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64

```


5. **5-Qadam: Kubernetes RBAC Sozlash:** Huquqlarni chegaralash (Security).
GitHub Runner'ining `default` ServiceAccount'i `argocd` namespace'i ichida **Application** resurslarini boshqara olishi uchun `infra/argocd/argocd-role.yaml` faylini qo'llaymiz:

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: runner-argocd-app-manager
  namespace: argocd
rules:
  - apiGroups: ["argoproj.io"]
    resources: ["applications"]
    verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: runner-argocd-app-binding
  namespace: argocd
subjects:
  - kind: ServiceAccount
    name: default
    namespace: actions-runner-system
roleRef:
  kind: Role
  name: runner-argocd-app-manager
  apiGroup: rbac.authorization.k8s.io

```

```bash
kubectl apply -f infra/argocd/argocd-role.yaml

```


---

## 🛠️ 3. GitHub Actions Continuous Deployment (CD) Pipeline

Kliningizdagi `self-hosted` runner orqali ArgoCD-ni tezkor Sync qilishning **2 xil professional usuli**:

### ⭐️ 1-Opsiya: ArgoCD CLI orqali Sync qilish (Tavsiya etiladi)

Xavfsiz va to'g'ridan-to'g'ri K8s ichki tarmog'i (`.svc.cluster.local`) orqali Sync yuborish:

```yaml
  cd:
    needs: ci
    runs-on: self-hosted
    steps:
      # 1. ArgoCD CLI mavjudligini tekshirish va o'rnatish
      - name: Install ArgoCD CLI
        run: |
          if ! command -v argocd &> /dev/null; then
            echo "ArgoCD CLI topilmadi, o'rnatilmoqda..."
            curl -sSL -o /tmp/argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
            sudo install -m 555 /tmp/argocd-linux-amd64 /usr/local/bin/argocd
            rm /tmp/argocd-linux-amd64
          fi

      # 2. ArgoCD Serverga Login bo'lish va Manifestni Sync qilish
      - name: ArgoCD Sync Application
        run: |
          argocd login argocd-server.argocd.svc.cluster.local:443 \
            --insecure \
            --grpc-web \
            --username "${{ secrets.ARGOCD_USERNAME }}" \
            --password "${{ secrets.ARGOCD_PASSWORD }}"

          # ArgoCD ilovasini darhol sync qilish va Pod'lar sog'lom bo'lishini kutish
          argocd app sync raffle --async
          argocd app wait raffle --health

```

---

### 2-Opsiya: Tayyor `argocd-action` ishlatish

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

## 🔄 GitOps Ishlash Mexanizmi (ArgoCD Application Flow)

```
[ Developer Push ] ➔ [ GitHub Actions CI ] (Build & Push Docker Image / Update Helm Values)
                                  │
                                  ▼
                     [ ArgoCD CLI Trigger (Sync) ]
                                  │
                                  ▼
[ ArgoCD Server ] ◄── Reads ── [ Git Repo (infra/helmfiles) ] ── Deploys ──► [ K8s Cluster (raffle ns) ]

```

1. **CI Job:** Koddagi o'zgarishni ko'radi, Docker image yaratadi va ECR/DockerHub'ga yuklaydi. Sung `values.yaml` dagi image tag'ini yangilab, Git'ga `push` qiladi.
2. **CD Job:** `argocd app sync` buyrug'i orqali ArgoCD serveriga signal yuboradi.
3. **ArgoCD Engine:** Git'dagi `infra/helmfiles` papkasini o'qib, `raffle` namespace'iga yangi versiyani **Zero-Downtime** rejimida joylaydi.