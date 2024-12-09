locals {
  lambda_path_include = ["**"]
  lambda_path_exclude = ["**/__pycache__/**"]

  # event dispatcher lambda
  event_dispatcher_source_path = "${path.module}/lambdas/event_dispatcher"
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
  create_iceberg_table_source_path = "${path.module}/lambdas/create_iceberg_table"
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
    WORKGROUP_NAME           = var.create_table_athena_workgroup_name
    GLUE_DATABASE_NAME       = var.glue_database_name
    GLUE_TABLE_NAME          = var.glue_table_name
    S3_BUCKET_TABLE_LOCATION = var.s3_bucket_table_location
    S3_TABLE_PREFIX          = var.s3_table_location_prefix
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
        "arn:aws:s3:::${var.s3_bucket_table_location}",
        "arn:aws:s3:::${var.s3_bucket_table_location}/${var.s3_table_location_prefix}*",
      ]
    }
  }

  cloudwatch_logs_retention_in_days = var.lambda_create_iceberg_table_log_group_retention_in_days


  image_uri = module.lambda_create_iceberg_table_builder.image_uri
}

resource "aws_lambda_invocation" "athena_query_observability_lambda_create_iceberg_table_invoke" {
  function_name = module.lambda_create_iceberg_table.lambda_function_name
  input = jsonencode({
    "force" : "true"
  })
  lifecycle_scope = "CRUD"
}

resource "aws_iam_role" "athena_observability_firehose_iceberg_role" {
  name = "${var.resource_prefix}-firehose-iceberg-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "firehose.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_role_policy" "athena_observability_firehose_iceberg_role_policy" {
  name = "${var.resource_prefix}-firehose-iceberg-role"
  role = aws_iam_role.athena_observability_firehose_iceberg_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "glue:GetTable",
          "glue:GetTableVersions",
          "glue:GetTableVersion",
          "glue:GetDatabase",
          "glue:UpdateTable",
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Effect = "Allow"
        Resource = [
          "arn:aws:s3:::${var.s3_bucket_table_location}",
          "arn:aws:s3:::${var.s3_bucket_table_location}/${var.s3_table_location_prefix}*",
          "arn:aws:s3:::${var.s3_bucket_table_location}/${var.firehose_s3_error_output_prefix}*",
        ]
      },
      {
        Action = [
          "logs:PutLogEvents",
          "logs:CreateLogStream",
          "logs:CreateLogGroup"
        ]
        Effect = "Allow"
        Resource = [
          "${aws_cloudwatch_log_group.athena_observability_firehose_log_group.arn}:*",
          "${aws_cloudwatch_log_group.athena_observability_firehose_log_group.arn}:*:*"
        ]
      },
    ]
  })
}

resource "aws_cloudwatch_log_group" "athena_observability_firehose_log_group" {
  name              = "/aws/kinesisfirehose/${var.resource_prefix}-iceberg-delivery"
  retention_in_days = var.firehose_log_group_retention_in_days
}

resource "aws_cloudwatch_log_stream" "athena_observability_firehose_log_stream" {
  name           = "DeliveryLogs"
  log_group_name = aws_cloudwatch_log_group.athena_observability_firehose_log_group.name
}

resource "aws_kinesis_firehose_delivery_stream" "athena_observability_iceberg_delivery" {
  name        = "${var.resource_prefix}-iceberg-delivery"
  destination = "iceberg"

  iceberg_configuration {
    role_arn    = aws_iam_role.athena_observability_firehose_iceberg_role.arn
    catalog_arn = "arn:${data.aws_partition.current.partition}:glue:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:catalog"

    buffering_size     = var.firehose_buffering_size
    buffering_interval = var.firehose_buffering_interval

    retry_duration = var.firehose_retry_duration

    s3_configuration {
      role_arn            = aws_iam_role.athena_observability_firehose_iceberg_role.arn
      bucket_arn          = "arn:aws:s3:::${var.s3_bucket_table_location}"
      error_output_prefix = var.firehose_s3_error_output_prefix
    }

    destination_table_configuration {
      database_name = var.glue_database_name
      table_name    = var.glue_table_name
      s3_error_output_prefix = var.firehose_s3_error_iceberg_prefix
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.athena_observability_firehose_log_group.name
      log_stream_name = aws_cloudwatch_log_stream.athena_observability_firehose_log_stream.name
    }
  }

  depends_on = [
    aws_lambda_invocation.athena_query_observability_lambda_create_iceberg_table_invoke
  ]
}

resource "aws_cloudwatch_event_rule" "athena_query_observability_lambda_event_bridge_rule" {
  name        = "${var.resource_prefix}-lambda-event-bridge-rule"
  description = "Capture Athena queries"

  state = var.event_bridge_rule_state

  event_pattern = jsonencode({
    source        = ["aws.athena"],
    "detail-type" = ["Athena Query State Change"]
    "detail" = {
      "currentState" = var.athena_query_state_change_event_pattern
    }
  })
}

module "athena_query_observability_lambda_event_dispatcher_builder" {
  source  = "terraform-aws-modules/lambda/aws//modules/docker-build"
  version = "7.15.0"

  create_ecr_repo = true
  ecr_repo        = "${var.resource_prefix}-event-dispatcher"
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
  image_tag     = local.event_dispatcher_dir_sha
  keep_remotely = true

  source_path = local.event_dispatcher_source_path

  triggers = {
    dir_sha = local.event_dispatcher_dir_sha
  }
}

module "athena_query_observability_event_dispatcher_lambda" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "7.15.0"

  function_name = "${var.resource_prefix}-event-dispatcher"
  description   = "It receives an event from Event Bridge and it dispatches to Firehose Delivery Stream"
  memory_size   = 128
  timeout       = 30

  create_package = false

  package_type = "Image"
  # when using arm64 be sure to use the right image in the Dockerfile
  architectures            = ["arm64"]
  attach_policy_statements = true

  environment_variables = {
    FIREHOSE_DELIVERY_STREAM = aws_kinesis_firehose_delivery_stream.athena_observability_iceberg_delivery.name
  }

  policy_statements = {
    athena = {
      effect = "Allow",
      actions = [
        "athena:GetQueryExecution",
        "athena:GetQueryExecutions"
      ],
      resources = [
        "*"
      ]
    }

    firehose = {
      effect = "Allow",
      actions = [
        "firehose:PutRecord",
        "firehose:PutRecordBatch"
      ],
      resources = [
        aws_kinesis_firehose_delivery_stream.athena_observability_iceberg_delivery.arn
      ]
    }
  }
  cloudwatch_logs_retention_in_days = var.lambda_event_dispatcher_log_group_retention_in_days

  image_uri = module.athena_query_observability_lambda_event_dispatcher_builder.image_uri
}

resource "aws_lambda_permission" "athena_query_observability_event_dispatcher_lambda_permission" {
  action        = "lambda:InvokeFunction"
  function_name = module.athena_query_observability_event_dispatcher_lambda.lambda_function_arn
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.athena_query_observability_lambda_event_bridge_rule.arn
}


resource "aws_cloudwatch_event_target" "athena_query_observability_event_lambda_target" {
  rule = aws_cloudwatch_event_rule.athena_query_observability_lambda_event_bridge_rule.name
  arn  = module.athena_query_observability_event_dispatcher_lambda.lambda_function_arn

  retry_policy {
    maximum_event_age_in_seconds = var.event_bridge_retry_policy_maximum_event_age_in_seconds
    maximum_retry_attempts       = var.event_bridge_retry_policy_maximum_retry_attempts
  }
}
