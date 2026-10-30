terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
  }

  backend "s3" {
    bucket         = "status-terraform-state"
    key            = "status-api/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  }
}

provider "aws" {
  region = "us-east-1"
}

variable "vpc_id" {
  type        = string
  description = "VPC that hosts the status API"
}

resource "aws_security_group" "api" {
  name        = "status-api"
  description = "Status API instances"
  vpc_id      = var.vpc_id
}
