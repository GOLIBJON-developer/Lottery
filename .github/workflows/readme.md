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


