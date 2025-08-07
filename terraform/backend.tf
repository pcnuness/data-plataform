terraform {
  backend "s3" {}
}

/*
# EXEC LOCAL
terraform {
  backend "s3" {
    bucket         = "381491977476-backend-iac-opentofu"
    key            = "pcnuness/containers-blog/eks-adr-kubernetes/cluster-kubernetes/terraform.tfstate"
    region         = "us-east-1"
  }
}
*/