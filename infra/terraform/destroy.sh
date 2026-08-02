#!/usr/bin/env bash
set -e
# Skript qayerdan chaqirilishidan qat'iy nazar, shu skript joylashgan papkaga o'tadi
cd "$(dirname "${BASH_SOURCE[0]}")"

echo "Ingress-nginx va ArgoCD o'chirilmoqda..."
helm uninstall ingress-nginx -n ingress-nginx || true
helm uninstall argocd -n argocd || true

VPC_ID=$(terraform output -raw vpc_id)

echo "AWS'da Load Balancer to'liq o'chishi kutilmoqda..."
while true; do
  COUNT=$(aws elbv2 describe-load-balancers \
    --query "length(LoadBalancers[?VpcId=='$VPC_ID'])" \
    --output text 2>/dev/null || echo 0)
  if [ "$COUNT" -eq 0 ]; then
    echo "Load Balancer yo'q, davom etamiz."
    break
  fi
  echo "Hali $COUNT ta LB bor, 15 soniyadan keyin qayta tekshiramiz..."
  sleep 15
done

echo "ENI'lar tozalanishi kutilmoqda..."
while true; do
  ENI_COUNT=$(aws ec2 describe-network-interfaces \
    --filters "Name=vpc-id,Values=$VPC_ID" "Name=status,Values=in-use" \
    --query "length(NetworkInterfaces[?contains(Description, 'ELB')])" \
    --output text 2>/dev/null || echo 0)
  [ "$ENI_COUNT" -eq 0 ] && break
  echo "Hali $ENI_COUNT ta ELB ENI bor, 15 soniyadan keyin qayta tekshiramiz..."
  sleep 15
done

echo "Toza, destroy boshlanmoqda."
terraform destroy --auto-approve