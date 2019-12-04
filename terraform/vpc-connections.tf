###############
# VPC connections
#
# This file establishes connections to any other VPCs we need to connect to.
# This is the supplier VPC and the Opentest VPC.
# Note that when not using Opentest, then the config for connecting to the
# Opentest VPC can be removed (this config is deliberately kept in this file
# to make it easier to remove).
#
# In this file, we assume that all the VPCs are in the same region, and are
# under the same account.
###############

##############
# Supplier VPC
##############

# VPC peering connection
resource "aws_vpc_peering_connection" "supplier_peering_connection" {
  peer_vpc_id = var.supplier_vpc_id
  vpc_id = aws_vpc.mhs_vpc.id
  auto_accept = true

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  tags = {
    Name = "${var.environment_id}-mhs-supplier-peering-connection"
    EnvironmentId = var.environment_id
  }
}

# Add a route to the MHS VPC in the supplier VPC route table
data "aws_ssm_parameter" "private_rtb" {
    name = "/NHS/${var.deductions_env}-${data.aws_caller_identity.current.account_id}/tf/deductions_private/private_rtb"
}

data "aws_ssm_parameter" "public_rtb" {
    name = "/NHS/${var.deductions_env}-${data.aws_caller_identity.current.account_id}/tf/deductions_private/public_rtb"
}

resource "aws_route" "private_supplier_to_mhs_route" {
  route_table_id = data.aws_ssm_parameter.private_rtb.value
  destination_cidr_block = aws_vpc.mhs_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.supplier_peering_connection.id
}

# Add a route to the supplier VPC in the MHS VPC private subnet route table
resource "aws_route" "mhs_to_supplier_route" {
  route_table_id = aws_vpc.mhs_vpc.main_route_table_id
  destination_cidr_block = data.aws_vpc.supplier_vpc.cidr_block
  vpc_peering_connection_id = aws_vpc_peering_connection.supplier_peering_connection.id
}

# Allow DNS resolution of the domain names defined in route53.tf in the supplier VPC
resource "aws_route53_zone_association" "supplier_hosted_zone_mhs_vpc_association" {
  zone_id = aws_route53_zone.mhs_hosted_zone.zone_id
  vpc_id = data.aws_vpc.supplier_vpc.id
}

# Allow outbound requests from MHS inbound security group to the Amazon MQ inbound queue
resource "aws_security_group_rule" "mhs_inbound_security_group_amazon_mq_egress_rule" {
  security_group_id = aws_security_group.mhs_inbound_security_group.id
  type = "egress"
  from_port = 5671
  to_port = 5671
  protocol = "tcp"
  # Not making any assumptions here about the internal structure of the supplier VPC.
  # This can be changed and made more specific to lock this down more.
  cidr_blocks = [
    data.aws_vpc.supplier_vpc.cidr_block]
  description = "Allow outbound requests to Amazon MQ inbound queue"
}

# Add a route to the supplier VPC in the MHS VPC public subnet route table
resource "aws_route" "mhs_public_to_supplier_route" {
  route_table_id = local.public_subnet_route_table
  destination_cidr_block = "10.20.0.0/16"
  vpc_peering_connection_id = aws_vpc_peering_connection.supplier_peering_connection.id
}

##############
# Opentest connectivity
##############

#TODO: conditional or generalize with PTL, it is only a different subnet

# Allow outbound HTTP requests from MHS outbound security group to Opentest
resource "aws_security_group_rule" "mhs_outbound_security_group_opentest_http_proxy_egress_rule" {
  security_group_id = aws_security_group.mhs_outbound_security_group.id
  type = "egress"
  from_port = 443
  to_port = 443
  protocol = "tcp"
  cidr_blocks = [
    var.opentest_cidr]
  description = "Allow outbound requests to the HTTP proxy to Opentest"
}

# Allow outbound LDAP requests from MHS route security group to Opentest
resource "aws_security_group_rule" "mhs_route_security_group_opentest_ldap_proxy_egress_rule" {
  security_group_id = aws_security_group.mhs_route_security_group.id
  type = "egress"
  from_port = 389
  to_port = 389
  protocol = "tcp"
  cidr_blocks = [
    var.opentest_cidr]
  description = "Allow outbound LDAP requests to Opentest"
}
