module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "myapp-eks-cluster"
  cluster_version = "1.34"

  subnet_ids = module.myapp-vpc.private_subnets
  vpc_id     = module.myapp-vpc.vpc_id

  enable_irsa                              = true
  cluster_endpoint_public_access           = true
  enable_cluster_creator_admin_permissions = true

  tags = {
    Environment = "dev"
    Terraform   = "true"
  }

  cluster_addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent    = true
      before_compute = true
    }
  }

  # EKS Managed Node Group(s)
  # eks_managed_node_group_defaults = {
  #   instance_types = ["t3.micro"]
  # }

  eks_managed_node_groups = {
    dev = {
      min_size       = 2
      desired_size   = 2
      max_size       = 3
      instance_types = ["t3.small"]
      labels = {
        role = "dev"
      }
    }
  }

  # Cluster yaratilishida VPC to'liq tayyor bo'lishini kutish (Dependency lock)
  depends_on = [
    module.myapp-vpc
  ]


}

output "vpc_id" {
  value = module.myapp-vpc.vpc_id
}
output "eks_cluster_name" {
  value = module.eks.cluster_name
}