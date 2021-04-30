resource "aws_ecs_cluster" "mhs_outbound_cluster" {
  name = "${var.environment}-${var.cluster_name}-mhs-outbound-cluster"

  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-outbound"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

resource "aws_cloudwatch_log_group" "mhs_outbound_log_group" {
  name = "/ecs/${var.environment}-${var.cluster_name}-mhs-outbound"
  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-outbound-log-group"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

resource "aws_ecs_task_definition" "mhs_outbound_task" {
  family = "${var.environment}-${var.cluster_name}-mhs-outbound"
  container_definitions = jsonencode(
  [
    {
      name = "mhs-outbound"
      image = "${local.ecr_address}/mhs-outbound:${var.build_id}"
      environment = var.mhs_outbound_http_proxy == "" ? concat(local.mhs_outbound_base_environment_vars,
      [
        {
        name = "DNS_SERVER_1",
        value = local.dns_ip_address_0
      },
        {
          name = "DNS_SERVER_2",
          value = local.dns_ip_address_1
        }]) : concat(local.mhs_outbound_base_environment_vars, [
        {
          name = "DNS_SERVER_1",
          value = local.dns_ip_address_0
        },
        {
          name = "DNS_SERVER_2",
          value = local.dns_ip_address_1
        },
        {
          name = "MHS_OUTBOUND_HTTP_PROXY"
          value = var.mhs_outbound_http_proxy
        },
        {
          name = "MHS_RESYNC_INITIAL_DELAY"
          value = var.mhs_resync_initial_delay
        }
      ])
      secrets = var.route_ca_certs_arn == "" ? local.mhs_outbound_base_secrets : concat(local.mhs_outbound_base_secrets, [
        {
          name = "MHS_SECRET_SPINE_ROUTE_LOOKUP_CA_CERTS",
          valueFrom = var.route_ca_certs_arn
        }
      ])
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group = aws_cloudwatch_log_group.mhs_outbound_log_group.name
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
    Name = "${var.environment}-mhs-outbound-task"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
  task_role_arn = local.task_role_arn
  execution_role_arn = local.execution_role_arn
}

resource "aws_ecs_service" "mhs_outbound_service" {
  name = "${var.environment}-${var.cluster_name}-mhs-outbound"
  cluster = aws_ecs_cluster.mhs_outbound_cluster.id
  deployment_maximum_percent = 200
  deployment_minimum_healthy_percent = 100
  desired_count = var.mhs_outbound_service_minimum_instance_count
  launch_type = "FARGATE"
  platform_version = "1.3.0"
  scheduling_strategy = "REPLICA"
  task_definition = aws_ecs_task_definition.mhs_outbound_task.arn

  network_configuration {
    assign_public_ip = false
    security_groups = [
      aws_security_group.mhs_outbound.id
    ]
    subnets = local.mhs_private_subnet_ids
  }

  load_balancer {
    # In the MHS outbound task definition, we define only 1 container, and for that container, we expose only 1 port
    # That is why in these 2 lines below we do "[0]" to reference that one container and port definition.
    container_name = jsondecode(aws_ecs_task_definition.mhs_outbound_task.container_definitions)[0].name
    container_port = 80
    target_group_arn = aws_lb_target_group.outbound_alb_target_group.arn
  }

  depends_on = [
    aws_lb.outbound_alb
  ]

  # Preserve the autoscaled instance count when this service is updated
  lifecycle {
    ignore_changes = [
      desired_count
    ]
  }
}

resource "aws_security_group" "mhs_outbound" {
  name = "${var.environment}-${var.cluster_name}-mhs-outbound"
  description = "The security group used to control traffic for the MHS outbound component."
  vpc_id = local.mhs_vpc_id

  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-outbound-sg"
    Environment = var.environment
    CreatedBy = var.repo_name
  }

  egress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [var.spine_cidr]
    description = "MHS outbound egress to SDS and spine"
  }

  egress {
    from_port = 53
    to_port = 53
    protocol = "udp"
    cidr_blocks = [local.mhs_vpc_cidr_block]
    description = "MHS outbound egress to DNS"
  }


  egress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    prefix_list_ids = [
      local.mhs_dynamodb_vpc_endpoint_prefix_list_id,
      local.mhs_s3_vpc_endpoint_prefix_list_id
    ]
    description = "MHS outbound egress to AWS VPC endpoints for dynamodb and s3 (gateway type)"
  }

  egress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [local.mhs_vpc_cidr_block]
    description = "MHS outbound egress to MHS VPC"
  }

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [local.mhs_vpc_cidr_block]
    description = "MHS outbound ingress from MHS VPC"
  }
}

resource "aws_lb" "outbound_alb" {
  # Name length limited to 32 chars
  name = "${var.environment}-${var.cluster_name}-mhs-out-alb"
  internal = true
  load_balancer_type = "application"
  subnets = local.mhs_private_subnet_ids
  security_groups = [
    aws_security_group.outbound_alb.id
  ]

  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-outbound-alb"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

resource "aws_lb_target_group" "outbound_alb_target_group" {
  name = "${var.environment}-${var.cluster_name}-mhs-outbound"
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
    Name = "${var.environment}-mhs-outbound-alb-target-group"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

# Listener for MHS outbound service's load balancer that forwards requests to the correct target group
resource "aws_lb_listener" "outbound_alb_listener" {
  load_balancer_arn = aws_lb.outbound_alb.arn
  port = 443
  protocol = "HTTPS"
  ssl_policy = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn = aws_acm_certificate.mhs_outbound_cert.arn

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.outbound_alb_target_group.arn
  }
}

# MHS outbound load balancer security group
resource "aws_security_group" "outbound_alb" {
  name = "${var.environment}-${var.cluster_name}-mhs-outbound-alb"
  description = "The security group used to control traffic for the MHS outbound component Application Load Balancer."
  vpc_id = local.mhs_vpc_id


  # Allow inbound traffic from MHS VPC
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [local.mhs_vpc_cidr_block]
    description = "ALB outbound ingress from MHS VPC"
  }

  # TODO: Restrict the ingress cidr block to deductions private
  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [var.allowed_mhs_clients]
    description = "ALB outbound ingress from MHS clients"
  }

  egress {
    from_port = 80
    to_port = 80
    cidr_blocks = [local.mhs_vpc_cidr_block]
    protocol = "tcp"
    description = "ALB outbound egress to MHS VPC"
  }

  tags = {
    Name = "${var.environment}-alb-outbound-sg"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

resource "aws_route53_record" "mhs_outbound_load_balancer_record" {
  zone_id = data.aws_ssm_parameter.environment_private_zone_id.value
  name = "outbound.${var.cluster_suffix}"
  type = "A"

  alias {
    name = aws_lb.outbound_alb.dns_name
    zone_id = aws_lb.outbound_alb.zone_id
    evaluate_target_health = false
  }
}

resource "aws_ssm_parameter" "outbound_url" {
  name = "/repo/${var.environment}/output/${var.repo_name}/${var.cluster_name}-mhs-outbound-url"
  type  = "String"
  value = "https://${aws_route53_record.mhs_outbound_load_balancer_record.name}.${data.aws_route53_zone.environment_private_zone.name}"
  tags = {
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

data "aws_ssm_parameter" "spine_org_code" {
  name = "/repo/dev/user-input/opentest-spine-org-code"
}


locals {
  mhs_spine_org_code   = data.aws_ssm_parameter.spine_org_code.value
  mhs_outbound_base_environment_vars = [
    {
      name = "MHS_LOG_LEVEL"
      value = var.mhs_log_level
    },
    {
      name = "MHS_STATE_TABLE_NAME"
      value = aws_dynamodb_table.mhs_state_table.name
    },
    {
      name = "MHS_SYNC_ASYNC_STATE_TABLE_NAME"
      value = aws_dynamodb_table.mhs_sync_async_table.name
    },
    {
      name = "MHS_RESYNC_RETRIES"
      value = var.mhs_resynchroniser_max_retries
    },
    {
      name = "MHS_RESYNC_INTERVAL"
      value = var.mhs_resynchroniser_interval
    },
    {
      name = "MHS_SPINE_ROUTE_LOOKUP_URL"
      value = "https://${aws_route53_record.mhs_route_load_balancer_record.name}.${data.aws_route53_zone.environment_private_zone.name}"
    },
    {
      name = "MHS_SPINE_ORG_CODE"
      value = local.mhs_spine_org_code
    },
    {
      name = "MHS_SPINE_REQUEST_MAX_SIZE"
      value = var.mhs_spine_request_max_size
    },
    {
      name = "MHS_FORWARD_RELIABLE_ENDPOINT_URL"
      value = var.mhs_forward_reliable_endpoint_url
    }
  ]
  mhs_outbound_base_secrets = [
    {
      name = "MHS_SECRET_PARTY_KEY"
      valueFrom = local.party_key_arn
    },
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
      valueFrom = local.ca_certs_arn
    }
  ]
}

resource "aws_acm_certificate" "mhs_outbound_cert" {
  domain_name       = "outbound.${var.cluster_suffix}.${data.aws_route53_zone.environment_public_zone.name}"

  validation_method = "DNS"

  tags = {
    CreatedBy   = var.repo_name
    Environment = var.environment
  }
}

resource "aws_route53_record" "mhs_outbound_cert_validation_record" {
  for_each = {
    for dvo in aws_acm_certificate.mhs_outbound_cert.domain_validation_options : dvo.domain_name => {
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

resource "aws_acm_certificate_validation" "mhs_outbound_cert_validation" {
  certificate_arn = aws_acm_certificate.mhs_outbound_cert.arn
  validation_record_fqdns = [for record in aws_route53_record.mhs_outbound_cert_validation_record : record.fqdn]
}