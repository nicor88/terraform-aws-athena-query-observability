locals {
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
