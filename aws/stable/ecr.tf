# ECR repository for Camunda images
resource "aws_ecr_repository" "camunda" {
  name                 = "${var.prefix}/camunda"
  image_tag_mutability = "IMMUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name        = "${var.prefix}-camunda-repository"
    Environment = var.prefix
  }
}

resource "aws_ecr_lifecycle_policy" "camunda" {
  repository = aws_ecr_repository.camunda.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "untagged"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}