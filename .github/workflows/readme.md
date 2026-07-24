# Quyida berilgan 7ta ishni ketma ketlikda bajaring kutilgan natijani olasiz.
# Required envs 
```
ARGOCD_PASSWORD
ARGOCD_USERNAME
DOCKERHUB_TOKEN
DOCKERHUB_USERNAME
NEXT_PUBLIC_SEPOLIA_RPC_URL
NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID
```

#  Installing Helm and ArgoCD. ArgoCD setups included.

# 1 Installing Helm From Apt (Debian/Ubuntu)
Members of the Helm community have contributed an Apt package for Debian/Ubuntu. This package is generally up to date. Thanks to Buildkite for hosting the repo.
```
HELM_BUILDKITE_APT_KEY_ID="DDF78C3E6EBB2D2CC223C95C62BA89D07698DBC6"

sudo apt-get install curl gpg apt-transport-https --yes

curl -fsSL https://packages.buildkite.com/helm-linux/helm-debian/gpgkey > "${TMPDIR:-/tmp}/helm.gpg"

# Ensure that the key ID matches to prevent a repository compromise from establishing an attacker controlled key
if [ "$(gpg --show-keys --with-colons "${TMPDIR:-/tmp}/helm.gpg" | awk -F: '$1 == "fpr" {print $10}' | head -n 1)" != "${HELM_BUILDKITE_APT_KEY_ID}" ]; then echo "ERROR: Unexpected Helm APT key ID: potential key compromise"; exit 1; fi

cat "${TMPDIR:-/tmp}/helm.gpg" | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/helm.gpg] https://packages.buildkite.com/helm-linux/helm-debian/any/ any main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list

sudo apt-get update
sudo apt-get install helm
```


# 2  Install helm ArgoCD
https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd

```
helm repo add argo https://argoproj.github.io/argo-helm
```

# 3 create argocd.yaml file
```
redis-ha:
  enabled: false

controller:
  replicas: 1

server:
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
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
      nginx.ingress.kubernetes.io/ssl-passthrough: "true"
      nginx.ingress.kubernetes.io/backend-protocol: "HTTPS"
    tls: true
```

# 4 this is deployment cmd
```
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace -f argocd.yaml
```
```
kubectl get ing -n argocd
```
you see this:
argocd.example.com

Windows: C://System32/drivers/etc/hosts
MacOS and Linux: /etc/hosts  add this:
127.0.0.1 argocd.example.com

mine is : kubectl port-forward service/argocd-server -n argocd 8080:443

----------------------------------------------------------------------------------------------------

# Configure GitHub runners that will run INSIDE of our local kubernetes cluster
https://github.com/actions/actions-runner-controller  >  quickstart guide
--------------------------------------------------------------------------------------



# 5 Actions Runner Controller Quickstart


Prerequisites
Create a K8s cluster, if not available.
1️⃣ Install cert-manager in your cluster. For more information, see "cert-manager."
```
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.8.2/cert-manager.yaml
```

*note:- This command uses v1.8.2. Please replace with a later version, if available.
You may also install cert-manager using Helm. For instructions, see "Installing with Helm."

2️⃣ Next, Generate a Personal Access Token (PAT) for ARC to authenticate with GitHub.

Login to your GitHub account and Navigate to "Create new Token."
Select repo.
Click Generate Token and then copy the token locally ( we’ll need it later).
Deploy and Configure ARC
1️⃣ Deploy and configure ARC on your K8s cluster. You may use Helm or Kubectl.

Helm deployment
Add repository
```
helm repo add actions-runner-controller https://actions-runner-controller.github.io/actions-runner-controller
```

Install Helm chart
```
helm upgrade --install --namespace actions-runner-system --create-namespace\
  --set=authSecret.create=true\
  --set=authSecret.github_token="REPLACE_YOUR_TOKEN_HERE"\
  --wait actions-runner-controller actions-runner-controller/actions-runner-controller
```

*note:- Replace REPLACE_YOUR_TOKEN_HERE with your PAT that was generated previously.

Kubectl deployment
2️⃣ Create the GitHub self hosted runners and configure to run against your repository.

Create a runnerdeployment.yaml file and copy the following YAML contents into it:

```
apiVersion: actions.summerwind.dev/v1alpha1
kind: RunnerDeployment
metadata:
  name: self-hosted-runners
spec:
  replicas: 1
  template:
    spec:
      repository: GOLIBJON-developer/Lottery
```

*note:- Replace "mumoshu/actions-runner-controller-ci" with the name of the GitHub repository the runner will be associated with.

Apply this file to your K8s cluster.

```
kubectl apply -n actions-runner-system -f runnerdeployment.yaml
```
# OR

```
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

🎉 We are done - now we should have self hosted runners running in K8s configured to your repository. 🎉

Next - lets verify our setup and execute some workflows.

Verify and Execute Workflows
1️⃣ Verify that your setup is successful:

```
kubectl get runners -n actions-runner-system
```

NAME                             REPOSITORY                             STATUS
example-runnerdeploy2475h595fr   mumoshu/actions-runner-controller-ci   Running

```
kubectl get pods -n actions-runner-system
```

NAME                           READY   STATUS    RESTARTS   AGE
example-runnerdeploy2475ht2qbr 2/2     Running   0          1m

--------------------------------------------------------------
# 6 ARGOCD CLI INSTALLATIONS

```
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd
rm argocd-linux-amd64
```

--------------------------------------------------------------------------------------------------------------
# 7 Kubernetes RBAC (Role-Based Access Control)
--------------------------------------------------------------------------------------------------------------

##  Runner uchun ClusterRole / Role yaratish

### 1-Yo'l: Faqat `argocd` namespace uchun Role berish (Eng xavfsiz va to'g'ri yo'l)

Terminalda yoki klasteringizga ulanib, quyidagi manifestni bitta faylga saqlab `kubectl apply -f` qiling:
infra/argocd/argocd-role.yaml file tayyor xolatda.
```kubectl apply -f argocd-role.yaml``` ni tersangiz bas

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

Bu manifest `actions-runner-system` namespace'idagi `default` ServiceAccount'ga faqat `argocd` namespace ichida **Application** resurslarini boshqarish huquqini beradi.

# E'tiboringiz uchun rahmat ! ! ! 
------------------------------------------------------------------
# CD bo'yicha qo'shimcha malumotlar
------------------------------------------------------------------

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



