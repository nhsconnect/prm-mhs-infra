locals {
  # IAM for ECS tasks:
  task_role_arn = aws_iam_role.mhs.arn
  execution_role_arn = aws_iam_role.mhs-ecs.arn
}

data "aws_iam_policy_document" "mhs-ecs-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = [
        "ecs-tasks.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "mhs-ecs" {
  name               = "mhs-${var.environment}-${var.cluster_name}-EcsTaskExecutionRole"
  assume_role_policy = data.aws_iam_policy_document.mhs-ecs-assume-role-policy.json
  tags = {
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

resource "aws_iam_role_policy_attachment" "ssm-readonly-attach" {
  role       = aws_iam_role.mhs-ecs.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMReadOnlyAccess"
}

resource "aws_iam_role_policy_attachment" "ecs-task-exec-attach" {
  role       = aws_iam_role.mhs-ecs.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "read-secrets" {
  statement {
    actions = [
      "ssm:GetParameter",
    ]

    resources = [
      "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/*",
    ]
  }

  statement {
    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:/repo/*"
    ]
  }
}

resource "aws_iam_policy" "read-secrets" {
  name   = "mhs-${var.environment}-${var.cluster_name}-read-secrets"
  policy = data.aws_iam_policy_document.read-secrets.json
}

resource "aws_iam_role_policy_attachment" "ecs-read-secrets-attach" {
  role       = aws_iam_role.mhs-ecs.name
  policy_arn = aws_iam_policy.read-secrets.arn
}

data "aws_iam_policy_document" "ecs-assume-role-policy" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = [
        "ecs.amazonaws.com",
        "ecs-tasks.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "mhs" {
  name               = "mhs-${var.environment}-${var.cluster_name}"
  assume_role_policy = data.aws_iam_policy_document.ecs-assume-role-policy.json
  tags = {
    Environment = var.environment
    CreatedBy = var.repo_name
  }
}

data "aws_iam_policy_document" "dynamodb-table-access" {
  statement {
    actions = [
      "dynamodb:*"
    ]

    resources = [
      "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.environment}-${var.cluster_name}-mhs-state",
      "arn:aws:dynamodb:${var.region}:${data.aws_caller_identity.current.account_id}:table/${var.environment}-${var.cluster_name}-mhs-sync-async-state"
    ]
  }
}

resource "aws_iam_policy" "dynamodb-table-access" {
  name   = "mhs-${var.environment}-${var.cluster_name}-dynamodb-table-access"
  policy = data.aws_iam_policy_document.dynamodb-table-access.json
}

resource "aws_iam_role_policy_attachment" "mhs_dynamo_attach" {
  role       = aws_iam_role.mhs.name
  policy_arn = aws_iam_policy.dynamodb-table-access.arn
}
