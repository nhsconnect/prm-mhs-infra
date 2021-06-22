# ElastiCache (Redis) is used by mhs-route to cache SDS queries
resource "aws_elasticache_replication_group" "elasticache_replication_group" {
  automatic_failover_enabled = true
  replication_group_id = "${var.environment}-${var.cluster_name}-rg"
  replication_group_description = "An ElastiCache cluster for ${var.cluster_name} in the environment: ${var.environment}"
  node_type = var.elasticache_node_type
  number_cache_clusters = length(local.mhs_private_subnet_ids)
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
  port = 6379
  subnet_group_name = aws_elasticache_subnet_group.elasticache_subnet_group.name
  security_group_ids = [
    aws_security_group.sds_cache.id
  ]

  tags = {
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

# The MHS ElastiCache subnet group. Defines the subnets that the ElastiCache cluster should place replicas in.
resource "aws_elasticache_subnet_group" "elasticache_subnet_group" {
  name = "${var.environment}-${var.cluster_name}-elasticache-subnet-group"
  description = "Subnet group for the ElastiCache cluster for ${var.cluster_name} in environment: ${var.environment}"
  subnet_ids = local.mhs_private_subnet_ids
}

# SDS cache security group
resource "aws_security_group" "sds_cache" {
  name = "${var.environment}-${var.cluster_name}-elasticache-subnet-group"
  description = "The security group used to control traffic for the SDS cache endpoint."
  vpc_id = local.mhs_vpc_id

  tags = {
    Name = "${var.environment}-sds-cache-sg"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

resource "aws_security_group_rule" "sds_cache_ingress_from_mhs_route" {
  type = "ingress"
  from_port = 6379
  to_port = 6379
  protocol = "tcp"
  security_group_id = aws_security_group.sds_cache.id
  source_security_group_id = aws_security_group.route_ecs_tasks_sg.id
}