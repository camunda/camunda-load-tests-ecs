resource "aws_iam_role" "ecs_task_execution" {
  name = "${var.prefix}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution_policy" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_service" {
  name = "${var.prefix}-ecs-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_role_policy" "ecs_service" {
  name   = "${var.prefix}-ecs-service-role-policy"
  role   = aws_iam_role.ecs_service.name
  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "elasticloadbalancing:*",
        "ec2:*",
        "ecs:*"
      ],
      "Resource": [
        "*"
      ]
    }
  ]
}
EOF
}

# Create a separate task role for EFS access
resource "aws_iam_role" "ecs_task_role" {
  name = "${var.prefix}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}


resource "aws_iam_policy" "efs_sc_access" {
  name = "${var.prefix}-efs-sc-access"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowDescribe",
        "Effect" : "Allow",
        "Action" : [
          "elasticfilesystem:DescribeAccessPoints",
          "elasticfilesystem:DescribeFileSystems",
          "elasticfilesystem:DescribeMountTargets",
          "ec2:DescribeAvailabilityZones"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "AllowCreateAccessPoint",
        "Effect" : "Allow",
        "Action" : [
          "elasticfilesystem:CreateAccessPoint"
        ],
        "Resource" : "*",
        "Condition" : {
          "Null" : {
            "aws:RequestTag/efs.csi.aws.com/cluster" : "false"
          },
          "ForAllValues:StringEquals" : {
            "aws:TagKeys" : "efs.csi.aws.com/cluster"
          }
        }
      },
      {
        "Sid" : "AllowTagNewAccessPoints",
        "Effect" : "Allow",
        "Action" : [
          "elasticfilesystem:TagResource"
        ],
        "Resource" : "*",
        "Condition" : {
          "StringEquals" : {
            "elasticfilesystem:CreateAction" : "CreateAccessPoint"
          },
          "Null" : {
            "aws:RequestTag/efs.csi.aws.com/cluster" : "false"
          },
          "ForAllValues:StringEquals" : {
            "aws:TagKeys" : "efs.csi.aws.com/cluster"
          }
        }
      },
      {
        "Sid" : "AllowDeleteAccessPoint",
        "Effect" : "Allow",
        "Action" : "elasticfilesystem:DeleteAccessPoint",
        "Resource" : "*",
        "Condition" : {
          "Null" : {
            "aws:ResourceTag/efs.csi.aws.com/cluster" : "false"
          }
        }
      },
      {
        "Sid" : "AllowClientMount",
        "Effect" : "Allow",
        "Action" : [
          "elasticfilesystem:ClientMount",
          "elasticfilesystem:ClientWrite"
        ],
        "Resource" : "*"
      }
    ]
  })

}

# Add ECS Execute Command permissions to task role
resource "aws_iam_policy" "ecs_exec_policy" {
  name = "${var.prefix}-ecs-exec-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ssmmessages:CreateControlChannel",
          "ssmmessages:CreateDataChannel",
          "ssmmessages:OpenControlChannel",
          "ssmmessages:OpenDataChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_exec_policy_attachment" {
  role       = aws_iam_role.ecs_task_role.name
  policy_arn = aws_iam_policy.ecs_exec_policy.arn
}

# Registry-read policy exported by the stable stack (used in both single- and
# dual-region modes; the secret is in eu-west-1, same region as region 0).
resource "aws_iam_role_policy_attachment" "registry_policy_attachment" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = data.terraform_remote_state.stable.outputs.registry_credentials_iam_policy
}

# Grant the execution role read access to the basic-auth password secret so the
# ECS agent can inject CAMUNDA_CLIENT_AUTH_PASSWORD. Only created when basic auth is enabled.
resource "aws_iam_role_policy" "camunda_auth_secret" {
  count = local.use_basic_auth ? 1 : 0
  name  = "${var.prefix}-camunda-auth-secret"
  role  = aws_iam_role.ecs_task_execution.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [{
        Effect   = "Allow"
        Action   = "secretsmanager:GetSecretValue"
        Resource = var.camunda_auth_password_secret_arn
      }],
      var.camunda_auth_password_kms_key_arn != "" ? [{
        Effect   = "Allow"
        Action   = "kms:Decrypt"
        Resource = var.camunda_auth_password_kms_key_arn
      }] : []
    )
  })
}

