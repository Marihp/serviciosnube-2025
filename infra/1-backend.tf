terraform {
  backend "s3" {
    bucket       = "tfstate-servicios-nube"
    key          = "nube/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
    profile      = "servicios-nube"
  }
}
