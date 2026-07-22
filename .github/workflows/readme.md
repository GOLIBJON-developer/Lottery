Xulosa — 3 strategiya taqqoslash
                    EC2+Ansible    EKS+Helm       EKS+ArgoCD
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

Amaliy tavsiya — qaysi branch qachon
bash# Har strategiyani alohida branch da sinash
git checkout -b deploy/ec2
git push origin deploy/ec2
# → deploy-ec2.yml ishga tushadi

git checkout -b deploy/eks-helm
git push origin deploy/eks-helm
# → deploy-eks-helm.yml ishga tushadi

git checkout -b deploy/eks-argocd
git push origin deploy/eks-argocd
# → deploy-eks-argocd.yml ishga tushadi
Bu — portfolio uchun uchala strategiyani alohida-alohida ko'rsatish imkonini beradi, real production da esa faqat bitta branch qoldirib, qolganlarini o'chir


