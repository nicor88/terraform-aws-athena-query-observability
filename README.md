# terraform-aws-athena-query-observability
Terraform module that makes Athena query history querable via Iceberg tables


## Context
The main idea of this module is to make Athena query history querable via Iceberg tables.

## Requirements

- Terraform 1.8.0+
- Docker 24.0.0+

## Resources created by this module
- Lambda function to create the Iceberg table
- Lambda function to dispatch Event Bridge notifications to Firhose
- Firehose to send notifications to S3 as Iceberg table

## Usage

```hcl
module "athena_query_observability_from_github" {
  source = "git::https://github.com/nicor88/terraform-aws-athena-query-observability?ref=v0.0.1"

  glue_database_name       = "athena_observability"
  glue_table_name          = "query_state_change_example"
  s3_bucket_table_location = "s3-data-bucket"
  s3_table_location_prefix = "athena_observability/query_state_change_example"

  firehose_s3_error_output_prefix = "athena_observability/query_state_change_example_errors"

  create_table_athena_workgroup_name        = "primary"
  create_table_athena_s3_output_bucket_name = "athena-query-results-bucket"
}
```
