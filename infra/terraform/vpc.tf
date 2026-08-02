provider "aws" {
  region = "us-east-1"
}

# vars
variable "vpc_cidr_block" {}
variable "private_subnet_cidr_blocks" {}
variable "public_subnet_cidr_blocks" {}
data "aws_availability_zones" "azs" {}

output "azs" {
  value = data.aws_availability_zones.azs.names
}

module "myapp-vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "myapp-vpc"
  cidr = var.vpc_cidr_block

  azs             = data.aws_availability_zones.azs.names
  private_subnets = var.private_subnet_cidr_blocks
  public_subnets  = var.public_subnet_cidr_blocks

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true
  # enable_vpn_gateway = true

  tags = {
    "kubernetes.io/cluster/myapp-eks-cluster" = "shared"
    # Terraform = "true"
    # Environment = "dev"
  }

  public_subnet_tags = {
    "kubernetes.io/cluster/myapp-eks-cluster" = "shared"
    "kubernetes.io/role/elb"                  = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/myapp-eks-cluster" = "shared"
    "kubernetes.io/role/internal-elb"         = 1

  }
}