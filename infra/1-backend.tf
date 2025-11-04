terraform {
  backend "s3" {
    bucket       = "tfstate-servicios-nube-1"
    key          = "nube/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
    profile      = "terraform-prod"
  }
}
