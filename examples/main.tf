module "athena_query_observability" {
  source = "../"

  resource_prefix          = "athena-query-observability-example"
  glue_database_name       = "athena_observability"
  glue_table_name          = "query_state_change_example"
  s3_bucket_table_location = "s3-data-bucket"
  s3_table_location_prefix = "athena_observability/query_state_change_example"

  firehose_s3_error_output_prefix = "athena_observability/query_state_change_example_errors"

  create_table_athena_workgroup_name        = "primary"
  create_table_athena_s3_output_bucket_name = "athena-query-results-bucket"
}
