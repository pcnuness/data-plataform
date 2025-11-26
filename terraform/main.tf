terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.94.1"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.36"
    }
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.17.0"
    }
  }
}

variable "name" {
  type = string
}

variable "eks_name" {
  type = string
}

variable "eks_version" {
  type = string
}

variable "region" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "tags" {
  type = map(string)
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

##########################################
# EKS Auth and Providers (for bootstrap)
##########################################

provider "aws" {
  region = var.region
}

data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
  depends_on = [module.eks]
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

##########################################
# VPC Module
##########################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }

  tags = local.tags
}

##########################################
# EKS Cluster Module
##########################################
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.35"

  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version
  enable_irsa     = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  authentication_mode                      = "API_AND_CONFIG_MAP"
  enable_cluster_creator_admin_permissions = true
  
  cluster_enabled_log_types              = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
  create_cloudwatch_log_group            = true
  cloudwatch_log_group_retention_in_days = 7

  node_security_group_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = null
  }

  node_security_group_additional_rules = {
    ingress_self_all = {
      description = "Node to node all ports/protocols"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    },
    ingress_cluster_to_node_all_traffic = {
      description                   = "Cluster API to Nodegroup all traffic"
      protocol                      = "-1"
      from_port                     = 0
      to_port                       = 0
      type                          = "ingress"
      source_cluster_security_group = true
    }
  }

  eks_managed_node_group_defaults = {
    attach_cluster_primary_security_group = true
    iam_role_attach_cni_policy = true
    iam_role_additional_policies = {
      AmazonEKSWorkerNodePolicy : "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
      AmazonEKS_CNI_Policy : "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
      AmazonEC2ContainerRegistryReadOnly : "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
      AmazonSSMManagedInstanceCore : "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    }
    capacity_type = "ON_DEMAND"
    update_config = {
      max_unavailable_percentage = 33
    }
    labels = {
      "worknodes"                               = "default"
      "cpe.plataform.com/node-group" = "critical-addons"
    }
    taints = {
      addons = {
        key    = "CriticalAddonsOnly"
        value  = "true"
        effect = "PREFER_NO_SCHEDULE"
      }
    }
    tags = {
      worknodes = "default"
      type      = "critical-addons"
    }

  }

  eks_managed_node_groups = {
    for idx, subnet in module.vpc.private_subnets :
    "managed-worknode-${idx}" => {
      subnet_ids              = [subnet]
      instance_types          = ["t3a.medium"]
      ebs_optimized           = true
      enable_monitoring       = true
      min_size                = 1
      max_size                = 3
      desired_size            = 1
      node_group_name         = "managed-worknodes-${idx}"
      description             = "EKS managed node group for worknodes (not managed by karpenter)"
      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 64
            volume_type           = "gp3"
            iops                  = 3000
            throughput            = 150
            encrypted             = true
            delete_on_termination = true
          }
        }
      }
      iam_role_attach_cni_policy = true
      iam_role_additional_policies = {
        AmazonEKSWorkerNodePolicy : "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
        AmazonEKS_CNI_Policy : "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
        AmazonEC2ContainerRegistryReadOnly : "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
        AmazonSSMManagedInstanceCore : "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
      }
    }
  }

  tags = local.tags
}


resource "random_password" "argocd_admin_password" {
  length           = 28
  special          = true
  override_special = "(_="
}

resource "null_resource" "argocd_admin_password" {
  triggers = {
    plain    = random_password.argocd_admin_password.result
    hash     = bcrypt(random_password.argocd_admin_password.result)
    modified = timestamp()
  }
  lifecycle {
    ignore_changes = [
      triggers["hash"],
      triggers["modified"]
    ]
  }
}

module "secrets_manager_argocd" {
  source  = "terraform-aws-modules/secrets-manager/aws"
  version = "~> 1.3"

  name                    = "/${local.cluster_name}/gitops/argocd"
  description             = "Information about ArgoCD login in ${local.cluster_name}"
  recovery_window_in_days = 7
  block_public_policy     = true
  secret_string = jsonencode({
    ARGOCD_ADMIN_PASSWORD = random_password.argocd_admin_password.result
    ARGOCD_ENDPOINT = "gitops.694137446771.realhandsonlabs.net"
  })
}


output "cluster_region" {
  description = "Região do cluster EKS"
  value       = var.region
}

output "cluster_name" {
  description = "Nome do cluster EKS"
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "oidc_provider_arn" {
  value = module.eks.oidc_provider_arn
}

output "kubectl_config" {
  value = "aws eks --region us-east-1 update-kubeconfig --name ${module.eks.cluster_name}"
}

output "eks_context_name" {
  description = "Nome do contexto EKS"
  value       = "arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${module.eks.cluster_name}"
}

output "argocd_url" {
  description = "URL do ArgoCD"
  value       = "https://gitops.694137446771.realhandsonlabs.net"
}

output "argocd_login_command" {
  description = "Comando de login no ArgoCD"
  value = <<-EOT
    argocd login https://gitops.694137446771.realhandsonlabs.net \
      --insecure \
      --username admin \
      --password $(kubectl get secret \
        -n argocd \
        argocd-initial-admin-secret \
        -o jsonpath="{.data.password}" \
        --context arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${module.eks.cluster_name} | \
        base64 -d)
  EOT
}

output "argocd_cluster_add_command" {
  description = "Comando para adicionar cluster no ArgoCD"
  value = <<-EOT
    argocd cluster add arn:aws:eks:${var.region}:${data.aws_caller_identity.current.account_id}:cluster/${module.eks.cluster_name} \
      --name eks-demo-project \
      --label environment=develop \
      --label enable_ingress-nginx=true \
      --annotation addons_repo_revision=develop \
      --annotation addons_repo_url=https://github.com/pcnuness/data-ops.git
  EOT
}
