#!/usr/bin/env bash
set -euo pipefail

REGION="us-east-1"
ECR_URL="371726673826.dkr.ecr.us-east-1.amazonaws.com"
REPO="dev-raffle-repo"
CONTAINER="dev-raffle-repo"

# Instance IAM role orqali login — static kalit kerak emas, token har safar yangi olinadi
aws ecr get-login-password --region "$REGION" | docker login --username AWS --password-stdin "$ECR_URL"

REMOTE_DIGEST=$(aws ecr describe-images --repository-name "$REPO" --image-ids imageTag=latest \
  --region "$REGION" --query 'imageDetails[0].imageDigest' --output text)

CURRENT_DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' "$CONTAINER" 2>/dev/null | cut -d'@' -f2 || echo "none")

if [ "$REMOTE_DIGEST" != "$CURRENT_DIGEST" ]; then
  echo "$(date) - yangi image topildi ($REMOTE_DIGEST), deploy qilinmoqda"
  docker pull "$ECR_URL/$REPO:latest"
  docker stop "$CONTAINER" 2>/dev/null || true
  docker rm "$CONTAINER" 2>/dev/null || true
  docker run -d --name "$CONTAINER" --restart unless-stopped -p 443:3000 "$ECR_URL/$REPO:latest"
else
  echo "$(date) - o'zgarish yo'q"
fi