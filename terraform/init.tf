provider "aws" {
  region = "us-west-1"
}

provider "aws" {
  alias  = "west2"
  region = "us-west-2"
}

terraform {
  required_version = "1.3.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.0"
    }
  }
  backend "s3" {
    bucket         = "wfs3labs-tf-state-bucket-uswest1"
    key            = "root"
    region         = "us-west-1"
  }
}
