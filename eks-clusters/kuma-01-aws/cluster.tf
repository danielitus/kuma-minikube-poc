locals {
  cluster_name = "kuma-01-aws"
}

module "vpc" {
  source = "git::ssh://git@github.com/reactiveops/terraform-vpc.git?ref=v5.0.1"

  aws_region    = "us-east-2"
  az_count      = 2
  aws_azs       = "us-east-2a, us-east-2b"
  vpc_cidr_base = "10.171"

  global_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

module "eks" {
  source       = "git::https://github.com/terraform-aws-modules/terraform-aws-eks.git?ref=v12.1.0"
  cluster_name = local.cluster_name
  vpc_id       = module.vpc.aws_vpc_id
  subnets      = module.vpc.aws_subnet_private_prod_ids

  node_groups = {
    eks_nodes = {
      desired_capacity = 1
      max_capacity     = 1
      min_capaicty     = 1

      instance_type = "t3.medium"
    }
  }

  manage_aws_auth = false
}
