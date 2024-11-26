variable "glue_database_name" {
  type = string

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

variable "create_table_athena_workgroup_name" {
  type        = string
  default     = "primary"
  description = "Name of the Athena workgroup where the table will be created"
}

variable "create_table_athena_s3_output_bucket_name" {
  type        = string
  description = "Name of the S3 bucket where the Athena query results will be stored"
}
