variable "data_location_bucket_name" {
  type        = string
  description = "S3 bucket location for the table"
}

variable "athena_query_results_bucket_name" {
  type        = string
  description = "S3 bucket name for the table"
}

module "athena_query_observability" {
  source = "../"

  resource_prefix          = "athena-query-observability-example"
  glue_database_name       = "athena_observability"
  glue_table_name          = "query_state_change_example"
  s3_bucket_table_location = var.data_location_bucket_name
  s3_table_location_prefix = "athena_observability/query_state_change_example"

  firehose_buffering_interval = 5
  firehose_buffering_size = 5
  firehose_s3_error_output_prefix = "athena_observability/query_state_change_example_errors"

  create_table_athena_workgroup_name        = "primary"
  create_table_athena_s3_output_bucket_name = var.athena_query_results_bucket_name

  # force table recreation
  # force_table_creation         = "true"
  # force_table_creation_trigger = "force_recreating_table"
  # firehose_name_suffix         = "-v2"
}
 