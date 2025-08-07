
# ==================================================================
# CONFIGURAÇÕES AMBIENTE DEV - data-plataform
# ==================================================================

# Configurações Básicas
name        = "data-plataform-dev"
eks_name    = "data-plataform-dev-eks"
eks_version = "1.31"
region      = "us-east-1"
environment = "develop"

# Configurações de Rede
vpc_cidr = "10.0.0.0/16"

# Tags do Ambiente
tags = {
  Environment = "dev"
  Project     = "data-plataform"
  ManagedBy   = "backstage-opentofu"
  Owner       = "pcnuness"
  Repository  = "data-plataform"
}
