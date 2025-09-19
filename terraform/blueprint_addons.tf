module "eks_addons" {
  source  = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.21"

  cluster_name      = local.cluster_name
  cluster_version   = local.cluster_version
  cluster_endpoint  = local.cluster_endpoint
  oidc_provider_arn = local.oidc_provider_arn

  eks_addons = {

    coredns = {
      addon_version        = local.aws_eks.cluster_addon_versions.coredns
      configuration_values = jsonencode(yamldecode(file("${path.root}/values/coredns.yaml")))
    }


    kube-proxy = {
      addon_version        = local.aws_eks.cluster_addon_versions.kube_proxy
      configuration_values = jsonencode(yamldecode(file("${path.root}/values/kube-proxy.yaml")))
    }


    aws-ebs-csi-driver = {
      addon_version            = local.aws_eks.cluster_addon_versions.aws_ebs_csi_driver
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
      configuration_values     = jsonencode(yamldecode(file("${path.root}/values/aws-ebs-csi-driver.yaml")))
    }


    eks-pod-identity-agent = {
      addon_version        = local.aws_eks.cluster_addon_versions.eks_pod_identity_agent
      configuration_values = jsonencode(yamldecode(file("${path.root}/values/eks-pod-identity-agent.yaml")))
    }

  }

  enable_aws_load_balancer_controller = true
  aws_load_balancer_controller = {
    name          = "aws-load-balancer-controller"
    namespace     = "kube-system"
    chart         = "aws-load-balancer-controller"
    chart_version = "1.13.0"
    repository    = "https://aws.github.io/eks-charts"
    lint          = true
    values = [
      templatefile("${path.root}/values/aws-load-balancer-controller.yaml.tftpl", {
        region = local.region
        vpc_id = local.vpc_id
      })
    ]
  }

  enable_ingress_nginx = true
  ingress_nginx = {
    name          = "ingress-nginx"
    chart_version = "4.12.1"
    repository    = "https://kubernetes.github.io/ingress-nginx"
    namespace     = "ingress-nginx"
    lint          = true
    values        = [templatefile("${path.root}/values/ingress-nginx.yaml", {})]
    wait          = true
  }


  enable_argocd = true
  argocd = {
    name          = "argocd"
    chart_version = "8.2.5"
    repository    = "https://argoproj.github.io/argo-helm"
    namespace     = "argocd"
    skip_crds     = false
    values = [
      templatefile("${path.root}/values/argocd.yaml.tftpl", {
        url_gitops_argocd           = "gitops.905418053603.realhandsonlabs.net"
        aws_acm_arn                 = "arn:aws:acm:us-east-1:905418053603:certificate/b96d9009-dbfb-4c5f-9086-2eb63f59bd0d"
        argocd_admin_password_mtime = null_resource.argocd_admin_password.triggers.modified
        argocd_admin_password       = null_resource.argocd_admin_password.triggers.hash
        aws_subnets_ids             = local.subnet_public_ids
        env_name                    = local.environment
        env_abbreviation            = upper(substr(local.environment, 0, 1))
      })
    ]
    depends_on = [
      module.eks_addons.aws_load_balancer_controller
    ]
  }

  depends_on = [module.eks]
}
