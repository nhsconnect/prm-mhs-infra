locals {
  error_logs_metric_name        = "ErrorCountInLogs"
  mhs_inbound_metric_namespace  = "MhsInbound"
  mhs_outbound_metric_namespace = "MhsOutbound"
}

resource "aws_cloudwatch_log_metric_filter" "mhs_inbound_log_metric_filter" {
  name           = "${var.environment}-mhs-inbound-error-logs"
  pattern        = "{ $.level = \"ERROR\" }"
  log_group_name = aws_cloudwatch_log_group.mhs_inbound_log_group.name

  metric_transformation {
    name          = local.error_logs_metric_name
    namespace     = local.mhs_inbound_metric_namespace
    value         = 1
    default_value = 0
  }
}

resource "aws_cloudwatch_log_metric_filter" "mhs_outbound_log_metric_filter" {
  name           = "${var.environment}-mhs-outbound-error-logs"
  pattern        = "{ $.level = \"ERROR\" }"
  log_group_name = aws_cloudwatch_log_group.mhs_outbound_log_group.name

  metric_transformation {
    name          = local.error_logs_metric_name
    namespace     = local.mhs_outbound_metric_namespace
    value         = 1
    default_value = 0
  }
}

resource "aws_cloudwatch_log_group" "mhs_inbound_log_group" {
  name = "/ecs/${var.environment}-${var.cluster_name}-mhs-inbound"
  tags = {
    Name        = "${var.environment}-${var.cluster_name}-mhs-inbound-log-group"
    Environment = var.environment
    CreatedBy   = var.repo_name
  }
}

resource "aws_cloudwatch_log_group" "mhs_outbound_log_group" {
  name = "/ecs/${var.environment}-${var.cluster_name}-mhs-outbound"
  tags = {
    Name        = "${var.environment}-${var.cluster_name}-mhs-outbound-log-group"
    Environment = var.environment
    CreatedBy   = var.repo_name
  }
}