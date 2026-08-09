terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.52.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

#-----VARIABLES-----
variable "vpc_cidr_block" {}
variable "subnet_cidr_block" {}
variable "avail_zone" {}
variable "env_prefix" {}
variable "my_ip" {}
variable "instance-type" {}
variable "publickey_location" {}

#-----RESOURCES (NETWORK) -----
resource "aws_vpc" "myapp-vpc" {
  cidr_block           = var.vpc_cidr_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "${var.env_prefix}-vpc"
  }
}

resource "aws_subnet" "myapp-subnet-1" {
  vpc_id            = aws_vpc.myapp-vpc.id
  cidr_block        = var.subnet_cidr_block
  availability_zone = var.avail_zone
  tags = {
    Name = "${var.env_prefix}-subnet-1"
  }
}

resource "aws_internet_gateway" "myapp-igw" {
  vpc_id = aws_vpc.myapp-vpc.id
  tags = {
    Name = "${var.env_prefix}-igw"
  }
}

resource "aws_default_route_table" "main-rtb" {
  default_route_table_id = aws_vpc.myapp-vpc.default_route_table_id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.myapp-igw.id
  }
  tags = {
    Name = "${var.env_prefix}-main-rtb"
  }
}

resource "aws_default_security_group" "default-sg" {
  vpc_id = aws_vpc.myapp-vpc.id

  # Faqat sizning IP manzilingizdan Ansible (SSH) orqali ulanishga ruxsat
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }
  
  # Ilova porti hamma uchun ochiq
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  
  egress {
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
    cidr_blocks     = ["0.0.0.0/0"]
    prefix_list_ids = []
  }
  tags = {
    Name = "${var.env_prefix}-default-sg"
  }
}

# ---------------------------------------------------


#----- GITHUB ACTIONS OIDC & IAM ROLE -----
# 1. GitHub OIDC Provider'ni AWS'ga ulash (Agar oldin ochilmagan bo'lsa)
# data "aws_iam_openid_connect_provider" "github" {
#   url = "https://token.actions.githubusercontent.com"
# }

# (Agar yuqoridagi data source xato bersa, demak AWS'da OIDC provider yo'q. Uni quyidagicha yaratasiz):
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# 2. GitHub Actions o'ziga oladigan IAM Role (ECR'ga push qilish huquqi bilan)
resource "aws_iam_role" "github_actions_role" {
  name = "${var.env_prefix}-github-actions-role"

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
          "token.actions.githubusercontent.com:sub" : "repo:GOLIBJON-developer/Lottery:*" # <-- O'z GitHub Username va Repozitoriy nomingizni yozing!
        }
      }
    }]
  })
}

# 3. Rolga ECR'ga yozish (Push) huquqlarini berish
resource "aws_iam_role_policy_attachment" "ecr_power_user" {
  role       = aws_iam_role.github_actions_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
}

# ---------------------------------------------------

#----- ECR (DOCKER REGISTRY) -----
resource "aws_ecr_repository" "myapp_ecr" {
  name                 = "${var.env_prefix}-raffle-repo"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

#----- IAM ROLE & INSTANCE PROFILE (YANGI QO'SHILDI) -----
# 1. EC2 uchun rol yaratish
resource "aws_iam_role" "ec2_role" {
  name = "${var.env_prefix}-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

# 2. Rolga ECR'dan faqat o'qish huquqini (pull) biriktirish
resource "aws_iam_role_policy_attachment" "ecr_readonly" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# 3. AWS Console (Session Manager) orqali brauzerdan SSH'siz kirish huquqini biriktirish (Tavsiya)
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# 4. Rolni EC2'ga biriktirish uchun profil yaratish
resource "aws_iam_instance_profile" "ec2_profile" {
  name = "${var.env_prefix}-ec2-profile"
  role = aws_iam_role.ec2_role.name
}

#----- EC2 INSTANCE -----
data "aws_ami" "latest-amazon-linux-image" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "ssh-key" {
  key_name   = "${var.env_prefix}-server-key"
  public_key = file(var.publickey_location)
}

resource "aws_instance" "myapp-server" {
  ami           = data.aws_ami.latest-amazon-linux-image.id
  instance_type = var.instance-type

  subnet_id                   = aws_subnet.myapp-subnet-1.id
  vpc_security_group_ids      = [aws_default_security_group.default-sg.id]
  availability_zone           = var.avail_zone
  associate_public_ip_address = true
  key_name                    = aws_key_pair.ssh-key.key_name

  # Yaratilgan profilni EC2 ga bog'lash (Shu orqali server parolsiz ECR bilan gaplashadi)
  iam_instance_profile = aws_iam_instance_profile.ec2_profile.name

  tags = {
    Name = "${var.env_prefix}-server"
  }
}

#----- OUTPUTS -----
output "aws_ami_id" {
  value = data.aws_ami.latest-amazon-linux-image.id
}

output "ec2_public_ip" {
  value = aws_instance.myapp-server.public_ip
}

output "ecr_repository_url" {
  value = aws_ecr_repository.myapp_ecr.repository_url
}

output "github_actions_role_arn" {
  value = aws_iam_role.github_actions_role.arn
}