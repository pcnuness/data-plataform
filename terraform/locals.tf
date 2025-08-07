locals {
  environment       = var.environment
  region            = var.region
  name              = var.name
  cluster_name      = var.eks_name
  cluster_version   = var.eks_version
  cluster_endpoint  = module.eks.cluster_endpoint
  oidc_provider_arn = module.eks.oidc_provider_arn
  vpc_id            = module.vpc.vpc_id
  vpc_cidr          = var.vpc_cidr
  subnet_public_ids = join(", ", module.vpc.public_subnets)
  azs               = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint = local.cluster_name,
    "karpenter.sh/discovery" = local.cluster_name
  }

  aws_eks = {
    cluster_name      = var.eks_name
    
    cluster_addon_versions = {
      
      coredns    = "v1.11.4-eksbuild.14"
      
      
      kube_proxy = "v1.31.2-eksbuild.3"
      
      
      eks_pod_identity_agent = "v1.3.7-eksbuild.2"
      
      
      aws_ebs_csi_driver = "v1.44.0-eksbuild.1"
      
    }
  }
}