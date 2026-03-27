# Registry credentials stored in AWS Secrets Manager
# Credentials are read from HashiCorp Vault (secret/data/products/camunda/harbor)
# and synced into AWS Secrets Manager for ECS task consumption.

data "vault_kv_secret_v2" "harbor" {
  mount = "secret"
  name  = "products/camunda/harbor"
}

resource "aws_secretsmanager_secret" "registry_credentials" {
  name                    = "${var.prefix}-registry-credentials"
  description             = "Registry credentials for ECS to pull images (synced from Vault)"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "registry_credentials" {
  secret_id = aws_secretsmanager_secret.registry_credentials.id
  secret_string = jsonencode({
    username = data.vault_kv_secret_v2.harbor.data["username"]
    password = data.vault_kv_secret_v2.harbor.data["password"]
  })
}

# IAM policy for ECS to access registry credentials
resource "aws_iam_policy" "registry_secrets_policy" {
  name = "${var.prefix}-registry-secrets-policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = [
          aws_secretsmanager_secret.registry_credentials.arn
        ]
      }
    ]
  })
}
