data "aws_ssm_parameter" "mq-app-username" {
  name = "/repo/${var.environment}/user-input/mq-app-username"
}

data "aws_ssm_parameter" "mq-app-password" {
  name = "/repo/${var.environment}/user-input/mq-app-password"
}

data "aws_ssm_parameter" "amqp-endpoint-active" {
  name = "/repo/${var.environment}/output/prm-deductions-infra/amqp-endpoint-active"
}

data "aws_ssm_parameter" "party-key" {
  name = "/repo/${var.environment}/user-input/${var.cluster_name}-mhs-party-key"
}

data "aws_ssm_parameter" "client-cert" {
  name = "/repo/${var.environment}/user-input/${var.cluster_name}-mhs-client-cert"
}

data "aws_ssm_parameter" "client-key" {
  name = "/repo/${var.environment}/user-input/${var.cluster_name}-mhs-client-key"
}

data "aws_ssm_parameter" "ca-certs" {
  name = "/repo/${var.environment}/user-input/${var.cluster_name}-mhs-ca-certs"
}

data "aws_ssm_parameter" "route-ca-certs" {
  name = "/repo/${var.environment}/user-input/${var.cluster_name}-mhs-route-ca-certs"
}

locals {
  inbound_queue_username_arn=data.aws_ssm_parameter.mq-app-username.arn
  inbound_queue_password_arn=data.aws_ssm_parameter.mq-app-password.arn
  #FIXME: mhs-inbound limitation: should use a failover connection string with both endpoints
  inbound_queue_host=replace(data.aws_ssm_parameter.amqp-endpoint-active.value, "amqp+ssl", "amqps")

  domain_suffix = "${var.environment}-${var.recipient_ods_code}"

  # MHS secrets to connect with spine
  party_key_arn=data.aws_ssm_parameter.party-key.arn
  client_cert_arn=data.aws_ssm_parameter.client-cert.arn
  client_key_arn=data.aws_ssm_parameter.client-key.arn
  ca_certs_arn=data.aws_ssm_parameter.ca-certs.arn
  route_ca_certs_arn=data.aws_ssm_parameter.route-ca-certs.arn
}

resource "aws_ecs_cluster" "mhs_inbound_cluster" {
  name = "${var.environment}-${var.cluster_name}-mhs-inbound-cluster"

  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-cluster"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

resource "aws_cloudwatch_log_group" "mhs_inbound_log_group" {
  name = "/ecs/${var.environment}-${var.cluster_name}-mhs-inbound"
  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-inbound-log-group"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

# MHS inbound ECS task definition
resource "aws_ecs_task_definition" "mhs_inbound_task" {
  family = "${var.environment}-${var.cluster_name}-mhs-inbound"
  container_definitions = jsonencode(
  [
    {
      name = "mhs-inbound"
      image = "${local.ecr_address}/mhs-inbound:${var.build_id}"
      environment = [
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
          name = "MHS_INBOUND_QUEUE_URL"
          value = "${local.inbound_queue_host}/${var.inbound_queue_name}"
        },
        {
          name = "MHS_INBOUND_RAW_QUEUE_URL"
          value = "${local.inbound_queue_host}/${var.inbound_raw_queue_name}"
        },
        {
          name = "DNS_SERVER_1",
          value = local.dns_ip_address_0
        },
        {
          name = "DNS_SERVER_2",
          value = local.dns_ip_address_1
        }

      ]
      secrets = [
        {
          name = "MHS_SECRET_INBOUND_QUEUE_USERNAME"
          valueFrom = local.inbound_queue_username_arn
        },
        {
          name = "MHS_SECRET_INBOUND_QUEUE_PASSWORD"
          valueFrom = local.inbound_queue_password_arn
        },
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
      essential = true
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group = aws_cloudwatch_log_group.mhs_inbound_log_group.name
          awslogs-region = var.region
          awslogs-stream-prefix = var.build_id
        }
      }
      portMappings = [
        # Port 443 is the port for inbound requests from Spine
        {
          containerPort = 443
          hostPort = 443
          protocol = "tcp"
        },
        # Port 80 is the port for healthcheck requests from the MHS inbound load balancer
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
    Name = "${var.environment}-mhs-inbound-task"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
  task_role_arn = local.task_role_arn
  execution_role_arn = local.execution_role_arn
}

# MHS inbound service that runs multiple of the MHS outbound task definition
# defined above
resource "aws_ecs_service" "mhs_inbound_service" {
  name = "${var.environment}-${var.cluster_name}-mhs-inbound"
  cluster = aws_ecs_cluster.mhs_inbound_cluster.id
  deployment_maximum_percent = 200
  deployment_minimum_healthy_percent = 100
  desired_count = var.mhs_inbound_service_minimum_instance_count
  launch_type = "FARGATE"
  platform_version = "1.3.0"
  scheduling_strategy = "REPLICA"
  task_definition = aws_ecs_task_definition.mhs_inbound_task.arn

  network_configuration {
    assign_public_ip = false
    security_groups = [
      aws_security_group.mhs_inbound_security_group.id
    ]
    subnets = local.mhs_private_subnet_ids
  }

  load_balancer {
    # In the MHS inbound task definition, we define only 1 container, and for that container, we expose 2 ports.
    # The first of these ports is 443, the port that we want to expose as it handles inbound requests from Spine.
    container_name = jsondecode(aws_ecs_task_definition.mhs_inbound_task.container_definitions)[0].name
    container_port = 443
    target_group_arn = aws_lb_target_group.inbound_https_nlb_target_group.arn
  }

  load_balancer {
    container_name = jsondecode(aws_ecs_task_definition.mhs_inbound_task.container_definitions)[0].name
    container_port = 80
    target_group_arn = aws_lb_target_group.inbound_http_nlb_target_group.arn
  }

  depends_on = [
    aws_lb.inbound_nlb
  ]

  # Preserve the autoscaled instance count when this service is updated
  lifecycle {
    ignore_changes = [
      desired_count
    ]
  }
}

# MHS inbound security group
resource "aws_security_group" "mhs_inbound_security_group" {
  name = "${var.environment}-mhs-inbound-sg"
  description = "The security group used to control traffic for the MHS Inbound component."
  vpc_id = local.mhs_vpc_id

  tags = {
    Name = "${var.environment}-mhs-inbound-sg"
    Environment = var.environment
    CreatedBy = var.repo_name
  }

  # We're allowing inbound requests from the private subnets as MHS inbound load balancer
  # can't have a security group for us to reference.

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [local.mhs_vpc_cidr_block]
    description = "Allow HTTPS inbound requests from MHS inbound load balancer"
  }

  ingress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [var.allowed_mhs_clients]
    description = "Allow HTTPS inbound requests from MHS clients"
  }

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [local.mhs_vpc_cidr_block]
    description = "Allow HTTP inbound requests from MHS inbound load balancer"
  }

  ingress {
    from_port = 80
    to_port = 80
    protocol = "tcp"
    cidr_blocks = [var.allowed_mhs_clients]
    description = "Allow HTTP inbound requests from MHS clients"
  }

  egress {
    from_port = 53
    to_port = 53
    protocol = "udp"
    cidr_blocks = [local.mhs_vpc_cidr_block]
    description = "MHS-inbound egress to DNS"
  }

  egress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    prefix_list_ids = [
      local.mhs_dynamodb_vpc_endpoint_prefix_list_id,
      local.mhs_s3_vpc_endpoint_prefix_list_id
    ]
    description = "MHS-inbound egress to AWS VPC endpoints for dynamodb and s3 (gateway type)"
  }

  egress {
    from_port = 443
    to_port = 443
    protocol = "tcp"
    cidr_blocks = [local.mhs_vpc_cidr_block]
    description = "MHS-inbound egress to MHS VPC. (Interface type VPC endpoints)"
  }

  egress {
    from_port = 5671
    to_port = 5671
    protocol = "tcp"
    cidr_blocks = [var.allowed_mhs_clients] #TODO: consider var rename
    description = "MHS-inbound egress to ActiveMQ queue servers"
  }
}

##############
# MHS inbound load balancer
##############

# Network load balancer for MHS inbound.
# MHS inbound tasks handle the TLS termination as they do TLS MA. This is why we
# have to use a network load balancer here and not an application load balancer,
# to passthrough the SSL traffic.
resource "aws_lb" "inbound_nlb" {
  name = "${var.environment}-${var.cluster_name}-mhs-inbound"
  internal = true
  load_balancer_type = "network"
  enable_cross_zone_load_balancing = true
  enable_deletion_protection = false

  subnet_mapping {
    subnet_id            = tolist(local.mhs_private_subnet_ids)[0]
    private_ipv4_address = var.nlb_private_ips[0]
  }

  subnet_mapping {
    subnet_id            = tolist(local.mhs_private_subnet_ids)[1]
    private_ipv4_address = var.nlb_private_ips[1]
  }

  subnet_mapping {
    subnet_id            = tolist(local.mhs_private_subnet_ids)[2]
    private_ipv4_address = var.nlb_private_ips[2]
  }

  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-inbound"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

# Public DNS record for the MHS inbound component
resource "aws_route53_record" "public_mhs_inbound_load_balancer_record" {
  count = var.setup_public_dns_record == "true" ? 1 : 0
  zone_id = data.aws_ssm_parameter.public_root_zone_id.value
  name = "mhs-inbound-${var.environment}-${lower(var.recipient_ods_code)}.mhs"
  type = "A"
  ttl = 600

  records = var.nlb_private_ips
}

# Target group for the network load balancer for MHS inbound port 443
# The MHS inbound ECS service registers it's tasks here.
resource "aws_lb_target_group" "inbound_https_nlb_target_group" {
  name = "${var.environment}-${var.cluster_name}-mhs-in-https" # "name" cannot be longer than 32 characters
  port = 443
  protocol = "TCP"
  target_type = "ip"
  vpc_id = local.mhs_vpc_id
  deregistration_delay = var.deregistration_delay

  health_check {
    protocol = "HTTP"
    port = 80
    path = "/healthcheck"
  }

  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-inbound-https"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

# Target group for the network load balancer for MHS inbound port 80
# The MHS inbound ECS service registers it's tasks here.
resource "aws_lb_target_group" "inbound_http_nlb_target_group" {
  name = "${var.environment}-${var.cluster_name}-mhs-in-http" # "name" cannot be longer than 32 characters
  port = 80
  protocol = "TCP"
  target_type = "ip"
  vpc_id = local.mhs_vpc_id
  deregistration_delay = var.deregistration_delay

  health_check {
    protocol = "HTTP"
    port = 80
    path = "/healthcheck"
  }

  tags = {
    Name = "${var.environment}-${var.cluster_name}-mhs-inbound-http"
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

# HTTPS Listener for MHS inbound load balancer that forwards requests to the correct target group
resource "aws_lb_listener" "inbound_nlb_listener" {
  load_balancer_arn = aws_lb.inbound_nlb.arn
  port = 443
  protocol = "TCP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.inbound_https_nlb_target_group.arn
  }
}

# HTTP Listener for MHS inbound load balancer that forwards requests to the correct target group
resource "aws_lb_listener" "inbound_http_nlb_listener" {
  load_balancer_arn = aws_lb.inbound_nlb.arn
  port = 80
  protocol = "TCP"

  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.inbound_http_nlb_target_group.arn
  }
}

resource "aws_route53_record" "mhs_inbound_load_balancer_record" {
  zone_id = local.mhs_route53_zone_id
  name = "mhs-inbound-${local.domain_suffix}.${local.mhs_route53_zone_name}"
  type = "A"

  alias {
    name = aws_lb.inbound_nlb.dns_name
    evaluate_target_health = false
    zone_id = aws_lb.inbound_nlb.zone_id
  }
}
