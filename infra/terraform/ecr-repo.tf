# --- ECR ---
resource "aws_ecr_repository" "myapp_ecr" {
  name                 = "raffle-app"
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# --- GITHUB OIDC & IAM ROLE ---
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1", "1c58a3a8518e8759bf075b76b750d4f2df264fcd"]
}
# (Agar yuqoridagi 'data' xato bersa, 'resource' qilib yarating)

resource "aws_iam_role" "github_actions_role" {
  name = "eks-github-actions-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = aws_iam_openid_connect_provider.github.arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" : "repo:GOLIBJON-developer/Lottery:*"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_power_user" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# --- OUTPUTS ---
output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_role.arn
}
output "ecr_repository_url" {
  value = aws_ecr_repository.myapp_ecr.repository_url
}