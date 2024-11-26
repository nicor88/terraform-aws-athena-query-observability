locals {
  s3_bucket_iceberg_table = regex("^s3://([^/]+)/?", var.s3_table_location_prefix)[0]

  lambda_path_include = ["**"]
  lambda_path_exclude = ["**/__pycache__/**"]

  # event dispatcher lambda
  event_dispatcher_source_path = "lambdas/event_dispatcher"
  event_dispatcher_files_include = setunion([
    for f in local.lambda_path_include : fileset(local.event_dispatcher_source_path, f)
  ]...)
  event_dispatcher_files_exclude = setunion([
    for f in local.lambda_path_exclude : fileset(local.event_dispatcher_source_path, f)
  ]...)
  event_dispatcher_files = sort(setsubtract(local.event_dispatcher_files_include, local.event_dispatcher_files_exclude))
  event_dispatcher_dir_sha = sha1(join("", [
    for f in local.event_dispatcher_files : filesha1("${local.event_dispatcher_source_path}/${f}")
  ]))

  # create iceberg table lambda
  create_iceberg_table_source_path = "lambdas/create_iceberg_table"
  create_iceberg_table_files_include = setunion([
    for f in local.lambda_path_include : fileset(local.create_iceberg_table_source_path, f)
  ]...)
  create_iceberg_table_files_exclude = setunion([
    for f in local.lambda_path_exclude : fileset(local.create_iceberg_table_source_path, f)
  ]...)
  create_iceberg_table_files = sort(setsubtract(local.create_iceberg_table_files_include, local.create_iceberg_table_files_exclude))
  create_iceberg_table_dir_sha = sha1(join("", [
    for f in local.create_iceberg_table_files : filesha1("${local.create_iceberg_table_source_path}/${f}")
  ]))
}

module "lambda_create_iceberg_table_builder" {
  source  = "terraform-aws-modules/lambda/aws//modules/docker-build"
  version = "7.15.0"

  create_ecr_repo = true
  ecr_repo        = "${var.resource_prefix}-create-iceberg-table"
  ecr_repo_lifecycle_policy = jsonencode({
    "rules" : [
      {
        "rulePriority" : 1,
        "description" : "Keep only the latest images",
        "selection" : {
          "tagStatus" : "any",
          "countType" : "imageCountMoreThan",
          "countNumber" : 5
        },
        "action" : {
          "type" : "expire"
        }
      }
    ]
  })

  use_image_tag = true
  image_tag     = local.create_iceberg_table_dir_sha
  keep_remotely = true

  source_path = local.create_iceberg_table_source_path

  triggers = {
    dir_sha = local.create_iceberg_table_dir_sha
  }
}

# creating a partitioned Iceberg table in Glue via Terraform is not possible: https://github.com/hashicorp/terraform-provider-aws/issues/36531
# Instead we use a lambda function that use Athena DDL to create the table, and then we invoke it via Terraform

module "lambda_create_iceberg_table" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "7.15.0"

  function_name = "${var.resource_prefix}-create-iceberg-table"
  description   = "Takes care of creating an Iceberg table in Glue Catalog to be used by Firehose Delivery Stream"
  memory_size   = 128
  timeout       = 60

  create_package = false

  package_type = "Image"
  # when using arm64 be sure to use the right image in the Dockerfile
  architectures            = ["arm64"]
  attach_policy_statements = true

  environment_variables = {
    WORKGROUP_NAME         = var.create_table_athena_workgroup_name
    GLUE_DATABASE_NAME     = var.glue_database_name
    GLUE_TABLE_NAME        = var.glue_table_name
    S3_BASE_TABLE_LOCATION = var.s3_table_location_prefix
  }

  policy_statements = {
    athena = {
      effect = "Allow",
      actions = [
        "athena:GetQueryExecution",
        "athena:GetQueryResults",
        "athena:StartQueryExecution",
      ],
      resources = [
        "*"
      ]
    }

    glue = {
      effect = "Allow",
      actions = [
        "glue:CreateTable",
        "glue:GetDatabase",
        "glue:GetTable",
        "glue:DeleteTable"
      ],
      resources = [
        "*"
      ]
    }

    s3_athena_query = {
      effect = "Allow",
      actions = [
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:PutObject",
      ],
      resources = [
        "arn:aws:s3:::${var.create_table_athena_s3_output_bucket_name}",
        "arn:aws:s3:::${var.create_table_athena_s3_output_bucket_name}/*"
      ]
    }

    s3_iceberg_table_location = {
      effect = "Allow",
      actions = [
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:PutObject",
      ],
      resources = [
        "arn:aws:s3:::${local.s3_bucket_iceberg_table}",
        "arn:aws:s3:::${local.s3_bucket_iceberg_table}/*",
      ]
    }
  }
  cloudwatch_logs_retention_in_days = 1

  image_uri = module.lambda_create_iceberg_table_builder.image_uri
}

resource "aws_lambda_invocation" "athena_query_observability_lambda_create_iceberg_table_invoke" {
  function_name = module.lambda_create_iceberg_table.lambda_function_name
  input = jsonencode({
    "force" : "true"
  })
  lifecycle_scope = "CRUD"
}
