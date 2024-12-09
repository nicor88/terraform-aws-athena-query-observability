variable "glue_database_name" {
  type        = string
  description = "Name of the glue database where the table will be created"
}

variable "glue_table_name" {
  type        = string
  description = "Table name containing query history"
}

variable "s3_table_location_prefix" {
  type        = string
  description = "Prefix ot the S3 location where the table data will be stored"
}

variable "s3_bucket_table_location" {
  type        = string
  description = "The name of the S3 bucket where the table will be stored"
}

variable "create_table_athena_workgroup_name" {
  type        = string
  default     = "primary"
  description = "Name of the Athena workgroup where the table will be created"
}

variable "create_table_athena_s3_output_bucket_name" {
  type        = string
  description = "Name of the S3 bucket where the Athena query results will be stored"
}

variable "resource_prefix" {
  type        = string
  default     = "athena-query-observability"
  description = "Prefix used to name the resources created by this module"
}

variable "firehose_log_group_retention_in_days" {
  type        = number
  default     = 1
  description = "Retention period for the firehose log group"
}

variable "firehose_buffering_size" {
  type        = number
  default     = 5
  description = "Buffering size for the firehose"
}

variable "firehose_buffering_interval" {
  type        = number
  default     = 10
  description = "Buffering interval for the firehose"
}

variable "firehose_retry_duration" {
  type        = number
  default     = 3600
  description = "Retry duration for the firehose"
}

variable "firehose_s3_error_output_prefix" {
  type        = string
  default     = "_errors"
  description = "Suffix for the error output of the firehose"
}

variable "firehose_s3_error_iceberg_prefix" {
  type        = string
  default     = "_iceberg_errors"
  description = "Suffix for the error output of the firehose"
}

variable "athena_query_state_change_event_pattern" {
  type        = list(string)
  default     = ["QUEUED", "RUNNING", "SUCCEEDED", "FAILED", "CANCELLED"]
  description = "Event pattern for the Athena query state change"
}

variable "event_bridge_rule_state" {
  type        = string
  default     = "ENABLED"
  description = "State of the event bridge rule"
}

variable "event_bridge_retry_policy_maximum_event_age_in_seconds" {
  type        = number
  default     = 1800
  description = "Maximum event age in seconds for the event bridge retry policy"
}

variable "event_bridge_retry_policy_maximum_retry_attempts" {
  type        = number
  default     = 15
  description = "Maximum retry attempts for the event bridge retry policy"
}

variable "lambda_create_iceberg_table_log_group_retention_in_days" {
  type        = number
  default     = 1
  description = "Retention period for the lambda create iceberg table log group"
}

variable "lambda_event_dispatcher_log_group_retention_in_days" {
  type        = number
  default     = 3
  description = "Retention period for the lambda event dispatcher log group"
}
