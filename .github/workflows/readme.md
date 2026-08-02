# Quyida berilgan ishlarni ketma ketlikda bajaring kutilgan natijani olasiz.
# Required envs 
```
AWS_ROLE_ARN_EKS
NEXT_PUBLIC_SEPOLIA_RPC_URL
NEXT_PUBLIC_WALLET_CONNECT_PROJECT_ID
```

#  Installing Helm and ArgoCD. ArgoCD setups included.
```
cd infra/terraform/
terraform apply --auto-approve
```
chiqgan malumotlar asosida kerakli github secrets to'ldiriladi
AWS_ROLE_ARN_EKS = "xxxxxxxxxxxxxxxxxxxxxxxxxxx"

EKS klasterga ulanish (AWS uchun shart)
Helm K8s bilan gaplasha olishi uchun avval terminalingizni EKS ga ulashingiz kerak:
```
cd ../../
aws eks update-kubeconfig --region us-east-1 --name myapp-eks-cluster
```


#  Installing Helm From Apt (Debian/Ubuntu)
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
#  AWS EKS ga Nginx Ingress Controller o'rnatish 
Siz argocd.yaml da ingressClassName: nginx ishlatyapsiz. Bu EKS da ishlashi uchun avval uni o'rnatamiz. Bu buyruq AWS da avtomatik ravishda Network Load Balancer (NLB) yaratib beradi:
```
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo update

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx --create-namespace \
  --set controller.service.type=LoadBalancer \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/aws-load-balancer-type"="nlb"
```
(O'rnatilgach, 
```
kubectl get svc -n ingress-nginx
```
 qilsangiz, AWS tomonidan berilgan uzun DNS nomini ko'rasiz).



#  Install helm ArgoCD
https://github.com/argoproj/argo-helm/tree/main/charts/argo-cd

# ArgoCD repozitoriyasini qo'shish
```
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
```

#  ArgoCD ni K8s ga o'rnatish (O'zgarishsiz)
```
cd infra/argocd/
helm upgrade --install argocd argo/argo-cd -n argocd --create-namespace -f argocd.yaml
```
```
kubectl get ing -n argocd
```
AWS Load Balancer manzilini olish
Terminalda quyidagi buyruqni ishga tushiring:

```
kubectl get svc -n ingress-nginx ingress-nginx-controller
```


terganingizda Sizga EXTERNAL-IP ustunida uzun AWS manzili beriladi (masalan: k8s-ingressn-xxx-xxx.elb.us-east-1.amazonaws.com). 
terminalga yozing

# Avval AWS manzilining IP'sini bilib oling (terminalda):

```Bash

ping k8s-ingressn-xxx-xxx.elb.us-east-1.amazonaws.com
```

(Bu sizga bitta IP manzil qaytaradi, masalan: 3.85.x.x)

## Kompyuteringizdagi hosts faylini oching:

Windows: Notepad'ni Administrator huquqi bilan ochib, ```C:\Windows\System32\drivers\etc\hosts``` faylini tahrirlang.

Mac/Linux: ```sudo nano /etc/hosts```

Faylning eng tagiga shu IP va domenni qo'shib saqlang:

```Plaintext
3.85.x.x  argocd.example.com
```

###  Brauzerda ochish va Parolni olish
Endi brauzeringizga kirib, [https://argocd.example.com](https://argocd.example.com) deb yozasiz.

⚠️ Muhim: Brauzer sizga "Your connection is not private" (Ulanishingiz xavfsiz emas) degan qizil xato beradi. Sababi, SSL sertifikati ArgoCD tomonidan avtomatik (self-signed) yaratilgan. Bunga parvo qilmang, "Advanced" -> "Proceed to argocd.example.com" ni bosing.

Tizimga kirish (Login/Password):

Username: ```admin```

Password: Parolni olish uchun terminalda shu buyruqni bering:

```
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d; echo
```

## Agarda node yetishmovchiligi bo'lsa buni kiriting
```
aws eks update-nodegroup-config \
  --cluster-name myapp-eks-cluster \
  --nodegroup-name dev-20260802021522809600000015 \
  --scaling-config minSize=2,desiredSize=3,maxSize=3 \
  --output json
  ```

### ArgoCD Application Manifest (O'zgarishsiz)
```
kubectl apply -f application.yaml
```
menda test holatida bo'lgani uchun branchni ```aws-eks-deploy``` deb berganman va ```application.yaml``` va ```.github/actions/ui-ci-cd.yaml``` filearida ``branch``larni shunga o'zgartirganman



#### 1-qadam: GitHub Actions'ni muvaffaqiyatli yakunlash

* Kodni `git push` qiling.
* GitHub Actions ishga tushib:
1. `raffle-ui` ni build qiladi va ECR'ga tashlaydi (`raffle-app:0.1.x`).
2. `infra/helmfiles/values.yaml` dagi tag'ni yangi versiyaga o'zgartiradi va uni GitHub'ga avtomatik commit qiladi.



#### 2-qadam: ArgoCD orqali Deploy qilish

* ArgoCD avtomatik tarzda (yoki siz ArgoCD UI'ga kirib **Sync** tugmasini bosish orqali) GitHub'dagi yangi o'zgarishni ko'radi.
* ArgoCD klaster ichida `raffle` nomli namespace ochib, `replicaCount: 1` talab qilganingizdek 2 ta Pod'ni (`ClusterIP` rejimida) ishga tushiradi.
* *Tekshirish uchun terminalda:* `kubectl get pods -n raffle` yozib, podlar `Running` holatida ekanligini ko'rasiz.

#### 3-qadam: Ingress va Domain (Host) sozlamasi

Siz `values.yaml` da quyidagicha yozilgan:

```yaml
ingress:
  enabled: true
  className: "nginx"
  host: raffle.yourdomain.com

```

Brauzerda `[https://raffle.yourdomain.com](https://raffle.yourdomain.com)` deb yozganingizda ilovangiz ochilishi uchun:

1. NGINX Ingress Controller AWS EKS'da ishlayotgan bo'lishi shart (oldingi qadamlarda o'rnatgan edik).
2. `raffle.yourdomain.com` manzilini o'sha NGINX Load Balancer'ning tashqi IP (External-IP) manziliga bog'lashingiz kerak.
* *Agar haqiqiy domeningiz bo'lmasa,* xuddi ArgoCD kabi kompyuteringizning `/etc/hosts` fayliga yozib turib sinashingiz mumkin:
```text
<NGINX_LOAD_BALANCER_IP>   raffle.yourdomain.com

```





Shu qadamlarni bajarsangiz, EKS klasteringizda Web3 Raffle ilovangiz to'liq va xavfsiz ishga tushadi!


## Kubernetes resurslarini tozalash
Terminalda klasterga ulanib, Helm relizlarini o'chirib yuboring (bu AWS'dagi NLB va IP larni avtomatik ravishda bo'shatadi):

Bash


# 1. To'liq tozalovchi scriptni ishga tushiramiz
```
cd ../terraform/
./destroy.sh
```
