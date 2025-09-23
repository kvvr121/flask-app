// Provider and caller identity are defined in main.tf

locals {
  project_name     = "flask-app"
  aws_region       = var.aws_region != null ? var.aws_region : "us-west-2"
  ecr_repo_uri     = "954747465428.dkr.ecr.us-west-2.amazonaws.com/flask-app-repo"
  eks_cluster_name = "flask-app-cluster"
  namespace        = "flask-app-prod"
  github_owner     = var.github_owner
  github_repo      = var.github_repo
  github_branch    = var.github_branch
  codestar_arn     = var.codestar_connection_arn
}

# Artifact bucket for this full pipeline
resource "aws_s3_bucket" "artifacts_full" {
  bucket        = "${local.project_name}-codepipeline-artifacts-full-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
}

resource "aws_iam_role" "codebuild_build_full_role" {
  name               = "${local.project_name}-codebuild-build-full-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "codebuild.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild_build_full_policy" {
  name = "${local.project_name}-codebuild-build-full-policy"
  role = aws_iam_role.codebuild_build_full_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:BatchGetImage",
          "ecr:DescribeRepositories"
        ], Resource = "*" },
      { Effect = "Allow", Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"], Resource = "*" },
      { Effect = "Allow", Action = ["s3:GetObject","s3:PutObject","s3:ListBucket"], Resource = "*" }
    ]
  })
}

resource "aws_iam_role" "codebuild_deploy_full_role" {
  name               = "${local.project_name}-codebuild-deploy-full-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "codebuild.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codebuild_deploy_full_policy" {
  name = "${local.project_name}-codebuild-deploy-full-policy"
  role = aws_iam_role.codebuild_deploy_full_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["eks:DescribeCluster"], Resource = "*" },
      { Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
      { Effect = "Allow", Action = ["logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"], Resource = "*" },
      { Effect = "Allow", Action = ["sts:AssumeRole"], Resource = "*" }
    ]
  })
}

resource "aws_codebuild_project" "build_full" {
  name         = "${local.project_name}-build-full"
  service_role = aws_iam_role.codebuild_build_full_role.arn
  artifacts { type = "CODEPIPELINE" }
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }
}

resource "aws_codebuild_project" "deploy_full" {
  name         = "${local.project_name}-deploy-full"
  service_role = aws_iam_role.codebuild_deploy_full_role.arn
  artifacts { type = "CODEPIPELINE" }
  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = false
    environment_variable {
      name  = "CLUSTER_NAME"
      value = local.eks_cluster_name
    }
    environment_variable {
      name  = "AWS_REGION"
      value = local.aws_region
    }
    environment_variable {
      name  = "NAMESPACE"
      value = local.namespace
    }
    environment_variable {
      name  = "ECR_URI"
      value = local.ecr_repo_uri
    }
    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
    }
    environment_variable {
      name  = "HEALTH_URL"
      value = "https://your-domain.example.com/health"
    }
    environment_variable {
      name  = "HEALTH_TIMEOUT"
      value = "60"
    }
  }
  source {
    type      = "CODEPIPELINE"
    buildspec = "deploy-buildspec.bluegreen.yml"
  }
}

resource "aws_iam_role" "codepipeline_full_role" {
  name               = "${local.project_name}-codepipeline-full-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "codepipeline.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codepipeline_full_policy" {
  name = "${local.project_name}-codepipeline-full-policy"
  role = aws_iam_role.codepipeline_full_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      { Effect = "Allow", Action = ["codebuild:BatchGetBuilds","codebuild:StartBuild"], Resource = "*" },
      { Effect = "Allow", Action = ["s3:GetObject","s3:PutObject","s3:ListBucket"], Resource = "*" }
    ]
  })
}

resource "aws_codepipeline" "full" {
  name     = "${local.project_name}-pipeline-full"
  role_arn = aws_iam_role.codepipeline_full_role.arn

  artifact_store {
    type     = "S3"
    location = aws_s3_bucket.artifacts_full.bucket
  }

  stage {
    name = "Source"
    action {
      name             = "GitHubV2Source"
      category         = "Source"
      owner            = "AWS"
      provider         = "CodeStarSourceConnection"
      version          = "1"
      output_artifacts = ["SourceArtifact"]
      configuration = {
        ConnectionArn    = local.codestar_arn
        FullRepositoryId = "${local.github_owner}/${local.github_repo}"
        BranchName       = local.github_branch
        DetectChanges    = "true"
      }
    }
  }

  stage {
    name = "Build"
    action {
      name             = "BuildAction"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      input_artifacts  = ["SourceArtifact"]
      output_artifacts = ["BuildArtifact"]
      version          = "1"
      configuration = {
        ProjectName = aws_codebuild_project.build_full.name
      }
    }
  }

  stage {
    name = "Deploy"
    action {
      name            = "DeployToEKS"
      category        = "Build"
      owner           = "AWS"
      provider        = "CodeBuild"
      input_artifacts = ["BuildArtifact"]
      version         = "1"
      configuration = {
        ProjectName = aws_codebuild_project.deploy_full.name
      }
    }
  }
}

## S3 source policy no longer needed after switching to GitHub Source; removed.


