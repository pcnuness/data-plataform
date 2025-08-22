module "aws_lb_controller_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.54"

  role_name                              = "${local.cluster_name}-aws-load-balancer-controller-irsa"
  attach_load_balancer_controller_policy = true

  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-load-balancer-controller"]
    }
  }

  role_policy_arns = {
    ElasticLoadBalancingReadOnly = "arn:aws:iam::aws:policy/ElasticLoadBalancingReadOnly"
  }

  tags = local.tags
}

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.54"

  role_name             = "${local.cluster_name}-aws-ebs-csi-driver-irsa"
  role_description      = "EKS IRSA for AWS EBS CSI Driver in ${local.cluster_name} cluster"
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}

module "efs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.54"

  role_name             = "${local.cluster_name}-efs-csi-controller-irsa"
  attach_efs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["kube-system:efs-csi-controller"]
    }
  }

  tags = local.tags
}


module "crossplane_irsa_aws" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.54"

  role_name = "${local.cluster_name}-crossplane-irsa"

  role_policy_arns = {
    policy = "arn:aws:iam::aws:policy/AdministratorAccess"
  }

  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["crossplane-system:provider-aws"]
    }
  }

  tags = local.tags
}

module "adot_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.54"

  role_name        = "${local.cluster_name}-adot-collector-irsa"
  role_description = "EKS IRSA for ADOT Collector in ${local.cluster_name} cluster"
  role_policy_arns = {
    prometheus = "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
    xray       = "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess"
    cloudwatch = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  }
  oidc_providers = {
    main = {
      provider_arn               = local.oidc_provider_arn
      namespace_service_accounts = ["opentelemetry:adot-collector"]
    }
  }
  depends_on = [module.eks]
}
 
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 20.35"
 
  cluster_name                    = local.cluster_name
  enable_v1_permissions           = true
  iam_role_use_name_prefix        = false
  iam_role_name                   = "${local.cluster_name}-karpenter-controller-irsa"
  node_iam_role_use_name_prefix   = false
  node_iam_role_name              = "${local.cluster_name}-karpenter-node-irsa"
  enable_pod_identity             = true
  create_pod_identity_association = true
  namespace                       = "karpenter"
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
  depends_on = [module.eks]
}
