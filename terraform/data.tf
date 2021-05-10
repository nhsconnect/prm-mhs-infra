# Discover the VPC and private subnets to deploy MHS in.
data "aws_vpc" "mhs" {
  filter {
    name = "tag:Name"
    values = ["${var.environment}-${var.cluster_name}-mhs-vpc"]
  }
}

data "aws_subnet_ids" "mhs_private" {
  vpc_id = local.mhs_vpc_id
  filter {
    name   = "tag:Name"
    values = ["${var.environment}-${var.cluster_name}-mhs-private-subnet-*"]
  }
}

data "aws_ssm_parameter" "dns_ip_address_0" {
    name = "/repo/${var.environment}/output/prm-deductions-infra/${var.cluster_name}-dns-ip-0"
}

data "aws_ssm_parameter" "dns_ip_address_1" {
    name = "/repo/${var.environment}/output/prm-deductions-infra/${var.cluster_name}-dns-ip-1"
}

data "aws_caller_identity" "current" {}

data "aws_vpc_endpoint" "mhs-dynamodb" {
  vpc_id       = local.mhs_vpc_id
  service_name = "com.amazonaws.${var.region}.dynamodb"
}

data "aws_vpc_endpoint" "mhs-s3" {
  vpc_id       = local.mhs_vpc_id
  service_name = "com.amazonaws.${var.region}.s3"
}

data "aws_ssm_parameter" "environment_private_zone_id" {
  name = "/repo/${var.environment}/output/prm-deductions-infra/environment-private-zone-id"
}

data "aws_route53_zone" "environment_private_zone" {
  zone_id = data.aws_ssm_parameter.environment_private_zone_id.value
}

data "aws_ssm_parameter" "environment_public_zone_id" {
  name = "/repo/${var.environment}/output/prm-deductions-infra/environment-public-zone-id"
}

data "aws_route53_zone" "environment_public_zone" {
  zone_id = data.aws_ssm_parameter.environment_public_zone_id.value
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  ecr_address = "${local.account_id}.dkr.ecr.${var.region}.amazonaws.com" # created in prm-deductions-base-infra

  mhs_vpc_cidr_block = data.aws_vpc.mhs.cidr_block
  mhs_vpc_id = data.aws_vpc.mhs.id
  mhs_private_subnet_ids = data.aws_subnet_ids.mhs_private.ids
  dns_ip_address_0 = data.aws_ssm_parameter.dns_ip_address_0.value
  dns_ip_address_1 = data.aws_ssm_parameter.dns_ip_address_1.value
  mhs_dynamodb_vpc_endpoint_prefix_list_id = data.aws_vpc_endpoint.mhs-dynamodb.prefix_list_id
  mhs_s3_vpc_endpoint_prefix_list_id = data.aws_vpc_endpoint.mhs-s3.prefix_list_id
}

data "aws_ssm_parameter" "public_root_zone_id" {
  name = "/repo/output/prm-deductions-base-infra/root-zone-id"
}
