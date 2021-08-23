locals {
  sgs_with_service_to_mhs_route = [aws_security_group.mhs_route_alb.id,
    aws_security_group.alb_to_mhs_route_ecs.id,
    aws_security_group.service_to_mhs_route.id,
    aws_security_group.vpn_to_mhs_route.id,
    aws_security_group.gocd_to_mhs_route.id]
  sgs_without_service_to_mhs_route = [  aws_security_group.mhs_route_alb.id,
    aws_security_group.alb_to_mhs_route_ecs.id,
    aws_security_group.vpn_to_mhs_route.id,
    aws_security_group.gocd_to_mhs_route.id]
  route_alb_sgs = var.deploy_service_to_mhs_sg ? local.sgs_with_service_to_mhs_route : local.sgs_without_service_to_mhs_route
}

resource "aws_ecs_cluster" "mhs_route_cluster" {
  name = "${var.environment}-${var.cluster_name}-mhs-route-cluster"

  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-cluster"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

resource "aws_cloudwatch_log_group" "mhs_route_log_group" {
  name = "/ecs/${var.environment}-${var.cluster_name}-mhs-route"
  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-route-log-group"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

resource "aws_ecs_task_definition" "mhs_route_task" {
  family = "${var.environment}-${var.cluster_name}-mhs-route"
  container_definitions = jsonencode(
  [
    {
      name = "mhs-route"
      image = "${local.ecr_address}/mhs-route:${var.build_id}"
      environment = [
        {
          name = "DNS_SERVER_1",
          value = local.dns_ip_address_0
        },
        {
          name = "DNS_SERVER_2",
          value = local.dns_ip_address_1
        },
        {
          name = "MHS_LOG_LEVEL"
          value = var.mhs_log_level
        },
        {
          name = "MHS_SDS_URL"
          value = var.spineroutelookup_service_sds_url
        },
        {
          name = "MHS_SDS_SEARCH_BASE"
          value = var.spineroutelookup_service_search_base
        },
        {
          name = "MHS_DISABLE_SDS_TLS"
          value = var.spineroutelookup_service_disable_sds_tls
        },
        {
          name = "MHS_SDS_REDIS_CACHE_HOST"
          value = aws_elasticache_replication_group.elasticache_replication_group.primary_endpoint_address
        },
        {
          name = "MHS_SDS_REDIS_CACHE_PORT"
          value = tostring(aws_elasticache_replication_group.elasticache_replication_group.port)
        }
      ]
      secrets = [
        {
          name = "MHS_SECRET_CLIENT_CERT"
          valueFrom = local.client_cert_arn
        },
        {
          name = "MHS_SECRET_CLIENT_KEY"
          valueFrom = local.client_key_arn
        },
        {
          name = "MHS_SECRET_CA_CERTS"
          valueFrom = local.route_ca_certs_arn
        }
      ]
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group = aws_cloudwatch_log_group.mhs_route_log_group.name
          awslogs-region = var.region
          awslogs-stream-prefix = var.build_id
        }
      }
      portMappings = [
        {
          containerPort = 80
          hostPort = 80
          protocol = "tcp"
        }
      ]
    }
  ]
  )
  cpu = "512"
  memory = "1024"
  network_mode = "awsvpc"
  requires_compatibilities = [
    "FARGATE"
  ]
  tags = {
    Name = "${var.environment}-mhs-route-task"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
  task_role_arn = local.task_role_arn
  execution_role_arn = local.execution_role_arn
}

resource "aws_ecs_service" "mhs_route_service" {
  name = "${var.environment}-${var.cluster_name}-mhs-route"
  cluster = aws_ecs_cluster.mhs_route_cluster.id
  deployment_maximum_percent = 200
  deployment_minimum_healthy_percent = 100
  desired_count = var.mhs_route_service_minimum_instance_count
  launch_type = "FARGATE"
  platform_version = "1.3.0"
  scheduling_strategy = "REPLICA"
  task_definition = aws_ecs_task_definition.mhs_route_task.arn

  network_configuration {
    assign_public_ip = false
    security_groups = [
      aws_security_group.route_ecs_tasks_sg.id
    ]
    subnets = local.mhs_private_subnet_ids
  }

  load_balancer {
    # In the MHS route task definition, we define only 1 container, and for that container, we expose only 1 port
    # That is why in these 2 lines below we do "[0]" to reference that one container and port definition.
    container_name = jsondecode(aws_ecs_task_definition.mhs_route_task.container_definitions)[0].name
    container_port = 80
    target_group_arn = aws_lb_target_group.route_alb_target_group.arn
  }

  depends_on = [
    aws_lb.route_alb
  ]

  # Preserve the autoscaled instance count when this service is updated
  lifecycle {
    ignore_changes = [
      desired_count
    ]
  }
}

resource "aws_security_group" "route_ecs_tasks_sg" {
  name        = "${var.environment}-${var.cluster_name}-mhs-route-ecs-tasks-sg"
  vpc_id      = local.mhs_vpc_id

  ingress {
    description = "MHS route ingress from ALB"
    protocol = "tcp"
    from_port = 80
    to_port = 80
    security_groups = [aws_security_group.mhs_route_alb.id]
  }

  egress {
    from_port = var.sds_port
    to_port = var.sds_port
    protocol = "tcp"
    cidr_blocks = [var.spine_cidr]
    description = "MHS route egress to SDS and spine"
  }

  egress {
    from_port = 53
    to_port = 53
    protocol = "udp"
    cidr_blocks = [local.mhs_vpc_cidr_block]
    description = "MHS route egress to DNS"
  }

  egress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    prefix_list_ids = [
      local.mhs_dynamodb_vpc_endpoint_prefix_list_id,
      local.mhs_s3_vpc_endpoint_prefix_list_id
    ]
    description = "MHS route egress to AWS VPC endpoints for dynamodb and s3 (gateway type)"
  }

  egress {
    from_port = 6379
    to_port = 6379
    protocol = "tcp"
    security_groups = [aws_security_group.sds_cache.id]
    description = "MHS route egress to elasticache"
  }

  egress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [local.mhs_vpc_cidr_block]
    description = "MHS route egress to MHS VPC"
  }

  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-route-ecs-tasks-sg"
    CreatedBy   = var.repo_name
    Environment = var.environment
  }
}

resource "aws_lb" "route_alb" {
  name = "${var.environment}-${var.cluster_name}-mhs-route-alb"
  internal = true
  load_balancer_type = "application"
  subnets = local.mhs_private_subnet_ids
  security_groups = local.route_alb_sgs

  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-route-alb"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

# Exists to be referred by the ECS task of mhs route
resource "aws_security_group" "mhs_route_alb" {
  name = "${var.environment}-${var.cluster_name}-mhs-route-alb"
  description = "mhs route ALB security group"
  vpc_id      = local.mhs_vpc_id

  egress {
    from_port = 80
    to_port = 80
    cidr_blocks = [local.mhs_vpc_cidr_block]
    protocol = "tcp"
    description = "ALB route egress to MHS VPC"
  }

  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-route-alb"
    CreatedBy   = var.repo_name
    Environment = var.environment
  }
}

resource "aws_security_group" "alb_to_mhs_route_ecs" {
  name        = "${var.environment}-${var.cluster_name}-alb-to-mhs-route-ecs"
  description = "Allows mhs route ALB connections to mhs route component task"
  vpc_id      = local.mhs_vpc_id

  egress {
    description = "Allow outbound connections to mhs route ECS Task"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    security_groups = [aws_security_group.route_ecs_tasks_sg.id]
  }

  tags = {
    Name = "${var.environment}-${var.cluster_name}-alb-to-mhs-route-ecs"
    CreatedBy   = var.repo_name
    Environment = var.environment
  }
}

resource "aws_security_group" "service_to_mhs_route" {
  name        = "${var.environment}-${var.cluster_name}-service-to-mhs-route"
  description = "controls access from repo services to MHS route"
  vpc_id      = local.mhs_vpc_id

  tags = {
    Name = "${var.environment}-${var.cluster_name}-service-to-mhs-route"
    CreatedBy   = var.repo_name
    Environment = var.environment
  }
}

resource "aws_ssm_parameter" "service_to_mhs_route" {
  count = var.deploy_service_to_mhs_sg ? 1 : 0
  name = "/repo/${var.environment}/output/${var.repo_name}/service-to-mhs-route-sg-id"
  type = "String"
  value = aws_security_group.service_to_mhs_route.id
  tags = {
    CreatedBy   = var.repo_name
    Environment = var.environment
  }
}

resource "aws_security_group" "vpn_to_mhs_route" {
  name        = "${var.environment}-${var.cluster_name}-vpn-to-mhs-route"
  description = "controls access from vpn to MHS route"
  vpc_id      = local.mhs_vpc_id

  ingress {
    description = "Allow vpn to access mhs-route ALB"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    security_groups = [data.aws_ssm_parameter.vpn_sg_id.value]
  }

  tags = {
    Name = "${var.environment}-${var.cluster_name}-vpn-to-mhs-route"
    CreatedBy   = var.repo_name
    Environment = var.environment
  }
}

resource "aws_security_group" "gocd_to_mhs_route" {
  name        = "${var.environment}-${var.cluster_name}-gocd-to-mhs-route"
  description = "controls access from gocd to MHS route"
  vpc_id      = local.mhs_vpc_id

  ingress {
    description = "Allow gocd to access mhs-route ALB"
    protocol    = "tcp"
    from_port   = 443
    to_port     = 443
    security_groups = [data.aws_ssm_parameter.gocd_sg_id.value]
  }

  tags = {
    Name = "${var.environment}-${var.cluster_name}-gocd-to-mhs-route"
    CreatedBy   = var.repo_name
    Environment = var.environment
  }
}

# Target group for the application load balancer for MHS route service
# The MHS route ECS service registers it's tasks here.
resource "aws_lb_target_group" "route_alb_target_group" {
  name = "${var.environment}-${var.cluster_name}-mhs-route"
  port = 80
  protocol = "HTTP"
  target_type = "ip"
  vpc_id = local.mhs_vpc_id
  deregistration_delay = var.deregistration_delay

  health_check {
    path = "/healthcheck"
    matcher = "200"
  }

  tags = {
    Name = "${var.environment}-mhs-route-alb-target-group"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

# Listener for MHS route service's load balancer that forwards requests to the correct target group
resource "aws_lb_listener" "route_alb_listener" {
  load_balancer_arn = aws_lb.route_alb.arn
  port = 443
  protocol = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-TLS-1-2-Ext-2018-06"
  certificate_arn = aws_acm_certificate.mhs_route_cert.arn

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.route_alb_target_group.arn
  }
}

resource "aws_route53_record" "mhs_route_load_balancer_record" {
  zone_id = data.aws_ssm_parameter.environment_private_zone_id.value
  name = "route.${var.cluster_suffix}"

  type = "A"

  alias {
    name = aws_lb.route_alb.dns_name
    zone_id = aws_lb.route_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_acm_certificate" "mhs_route_cert" {
  domain_name       = "route.${var.cluster_suffix}.${data.aws_route53_zone.environment_public_zone.name}"

  validation_method = "DNS"

  tags = {
    CreatedBy   = var.repo_name
    Environment = var.environment
  }
}

resource "aws_route53_record" "mhs_route_cert_validation_record" {
  for_each = {
    for dvo in aws_acm_certificate.mhs_route_cert.domain_validation_options : dvo.domain_name => {
    name   = dvo.resource_record_name
    record = dvo.resource_record_value
    type   = dvo.resource_record_type
  }
}

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = data.aws_ssm_parameter.environment_public_zone_id.value
}

resource "aws_acm_certificate_validation" "mhs_route_cert_validation" {
  certificate_arn = aws_acm_certificate.mhs_route_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.mhs_route_cert_validation_record : record.fqdn]
}

resource "aws_ssm_parameter" "route_url" {
  name = "/repo/${var.environment}/output/${var.repo_name}/${var.cluster_name}-mhs-route-url"
  type  = "String"
  value = "https://${aws_route53_record.mhs_route_load_balancer_record.name}.${data.aws_route53_zone.environment_private_zone.name}"
  tags = {
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

