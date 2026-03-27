locals {
  camunda_image         = var.camunda_image
  oc_task_desired_count = 3
  
  # Use registry credentials when provided
  use_registry_credentials = var.registry_username != "" && var.registry_password != ""
  
  # Determine if this is an ECR image (no registry credentials needed)
  is_ecr_image = strcontains(local.camunda_image, ".dkr.ecr.") && strcontains(local.camunda_image, ".amazonaws.com")
}

# Registry credentials  
resource "aws_secretsmanager_secret" "registry_credentials" {
  count       = local.use_registry_credentials ? 1 : 0
  name        = "${var.prefix}-registry-credentials"
  description = "Registry credentials for ECS tasks"
}

resource "aws_secretsmanager_secret_version" "registry_credentials" {
  count     = local.use_registry_credentials ? 1 : 0
  secret_id = aws_secretsmanager_secret.registry_credentials[0].id
  secret_string = jsonencode({
    username = var.registry_username
    password = var.registry_password
  })
}

module "orchestration_cluster" {
  # clickable link
  # https://github.com/camunda/camunda-deployment-references/commit/d15e9e10b97b52052e735ab21dc449dbfe681170
  source = "git::https://github.com/camunda/camunda-deployment-references.git//aws/modules/ecs/fargate/orchestration-cluster?ref=d15e9e10b97b52052e735ab21dc449dbfe681170"

  prefix              = "${var.prefix}-oc" # s3 bucket name in workflow destroy step must be updated as well
  ecs_cluster_id      = data.terraform_remote_state.stable.outputs.ecs_cluster_id
  vpc_id              = data.terraform_remote_state.stable.outputs.vpc_id
  vpc_private_subnets = data.terraform_remote_state.stable.outputs.vpc_private_subnets
  aws_region          = "eu-west-1"

  efs_throughput_mode                 = "provisioned"
  efs_provisioned_throughput_in_mibps = 60
  nlb_arn                             = aws_lb.grpc.arn
  ecs_task_execution_role_arn         = aws_iam_role.ecs_task_execution.arn
  alb_listener_http_webapp_arn        = aws_lb_listener.http_webapp.arn
  alb_listener_http_management_arn    = aws_lb_listener.http_management.arn
  enable_alb_http_webapp_listener_rule     = true
  enable_alb_http_management_listener_rule = true
  image                               = local.camunda_image

  task_desired_count = local.oc_task_desired_count

  environment_variables = [
    {
      name  = "CAMUNDA_CLUSTER_REPLICATIONFACTOR"
      value = "3"
    },
    {
      name  = "CAMUNDA_CLUSTER_PARTITIONCOUNT"
      value = "3"
    },
    # do not initialize segment  with zeroes
    {
      name  = "CAMUNDA_CLUSTER_RAFT_SEGMENT_PREALLOCATION_STRATEGY"
      value = "NOOP"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_TYPE"
      value = "rdbms"
    },
    {
      name = "CAMUNDA_PROCESSING_FLOWCONTROL_WRITE_ENABLED",
      value = "true"
    },
    {
      name = "CAMUNDA_PROCESSING_FLOWCONTROL_WRITE_LIMIT" , 
      value = "10000"
    },
    { 
      name = "CAMUNDA_PROCESSING_FLOWCONTROL_WRITE_THROTTLE_ENABLED", 
      value = "true"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_URL"
      value = "jdbc:postgresql://${module.postgresql.aurora_endpoint}:5432/camunda"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_USERNAME"
      value = "camunda_admin"
    },
    {
      name  = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_AUTODDL"
      value = "true"
    },
    {
      name = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_HISTORY_DEFAULTHISTORYTTL"
      value = "P1D"
    },
    {
      name  = "CAMUNDA_REST_QUERY_ENABLED"
      value = "false"
    },
    {
      name  = "CAMUNDA_PERSISTENT_SESSIONS_ENABLED"
      value = "false"
    },
    {
      name  = "CAMUNDA_DATABASE_SCHEMA_MANAGER_CREATE_SCHEMA"
      value = "false"
    },
    {
      name  = "SPRING_PROFILES_ACTIVE"
      value = "broker,standalone"
    },
    {
      name  = "CAMUNDA_SECURITY_AUTHENTICATION_METHOD"
      value = "basic"
    },
    {
      name  = "CAMUNDA_SECURITY_AUTHENTICATION_UNPROTECTEDAPI"
      value = "true"
    },
    {
      name  = "CAMUNDA_SECURITY_AUTHORIZATIONS_ENABLED"
      value = "false"
    },
    {
      name  = "CAMUNDA_CLUSTER_RAFT_MAXAPPENDSPERFOLLOWER"
      value = "2"
    },
    {
      name  = "CAMUNDA_LOG_LEVEL"
      value = "INFO"
    }
    
  ]

  secrets = [
    {
      name      = "CAMUNDA_DATA_SECONDARYSTORAGE_RDBMS_PASSWORD"
      valueFrom = aws_secretsmanager_secret.db_admin_password.arn
    }
  ]

  # Registry credentials logic:
  # 1. ECR images need no credentials (IAM handles it)
  # 2. Registry credentials when provided
  # 3. Fallback to stable state credentials for registry.camunda.cloud
  registry_credentials_arn = local.is_ecr_image ? "" : (
    local.use_registry_credentials ? aws_secretsmanager_secret.registry_credentials[0].arn : (
      strcontains(local.camunda_image, "registry.camunda.cloud") ? data.terraform_remote_state.stable.outputs.registry_credentials_arn : ""
    )
  )

  service_security_group_ids = [
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_camunda_ports"],
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_80_443"],
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_9600"],
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_remote_packages"],
    data.terraform_remote_state.stable.outputs.security_groups_id["allow_efs"]
  ]
  efs_security_group_ids = [data.terraform_remote_state.stable.outputs.security_groups_id["allow_efs"]]


  extra_task_role_attachments = strcontains(local.camunda_image, "registry.camunda.cloud") ? [
    data.terraform_remote_state.stable.outputs.registry_credentials_iam_policy
  ] : []
}
