
module "dns" {
    source = "./dns"
    dns_global_forward_server = cidrhost(local.mhs_vpc_cidr_block, 2) # AWS DNS - second IP in the subnet
    dns_hscn_forward_server_1 = var.dns_hscn_forward_server_1
    dns_hscn_forward_server_2 = var.dns_hscn_forward_server_2
    dns_forward_zone          = var.dns_forward_zone
    ecr_address               = local.ecr_address
    unbound_image_version     = var.unbound_image_version
    subnet_ids                = local.subnet_ids
    vpc_id                    = local.mhs_vpc_id
    allowed_cidr              = local.mhs_vpc_cidr_block
    ssh_keypair_name          = aws_key_pair.mhs-key.key_name
    environment            = var.environment

    # workaround to force endpoint to be created first
    mock_input = aws_vpc_endpoint.ecr_endpoint.id
}
