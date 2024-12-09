import datetime
import logging
import os
import uuid

import boto3
from botocore.exceptions import ClientError
from pyathena import connect

logger = logging.getLogger()
logger.setLevel(logging.INFO)

WORKGROUP = os.environ.get('WORKGROUP', 'primary')

FORCE_TABLE_CREATION = os.environ.get('FORCE_TABLE_CREATION', 'true').lower() == 'true'
GLUE_DATABASE_NAME = os.environ['GLUE_DATABASE_NAME']
GLUE_TABLE_NAME = os.environ.get('GLUE_TABLE_NAME', 'query_history')
S3_BUCKET_TABLE_LOCATION = os.environ['S3_BUCKET_TABLE_LOCATION']
S3_TABLE_PREFIX = os.environ['S3_TABLE_PREFIX']
glue_client = boto3.client('glue')


def table_exists(database_name, table_name):
    try:
        response = glue_client.get_table(DatabaseName=database_name, Name=table_name)

        logger.info(f"Table '{table_name}' exists in database '{database_name}'.")
        return True
    except ClientError as e:
        if e.response['Error']['Code'] == 'EntityNotFoundException':
            logger.info(f"Table '{table_name}' does not exist in database '{database_name}'.")
            return False
        else:
            raise


def get_create_table_statement(database_name, table_name, s3_table_location):
    return f"""
    CREATE TABLE {database_name}.{table_name} (
        event_id string,
        event_date date,
        event_timestamp string,
        query_execution_id string,
        workgroup_name string,
        current_state string,
        previous_state string,
        statement_type string,
        substatement_type string,
        query string,
        query_statistics string,
        submission_timestamp string,
        completion_timestamp string,
        engine_version string
    )
    PARTITIONED BY (event_date) 
    LOCATION '{s3_table_location}' 
    TBLPROPERTIES (
        'table_type'='ICEBERG',
        'format'='parquet',
        'write_compression'='zstd'
    );
    """


def handler(event, context):
    logger.info('Event: {}'.format(event))
    s3_table_location = os.path.join('s3://', S3_BUCKET_TABLE_LOCATION, S3_TABLE_PREFIX, str(uuid.uuid4()) + '/')
    logger.info(f'S3 table location: {s3_table_location}')

    create_table_statement = get_create_table_statement(GLUE_DATABASE_NAME, GLUE_TABLE_NAME, s3_table_location)
    cursor = connect(work_group=WORKGROUP).cursor()

    if not table_exists(GLUE_DATABASE_NAME, GLUE_TABLE_NAME):
        logger.info(f"Table '{GLUE_TABLE_NAME}' does not exist in database '{GLUE_DATABASE_NAME}', creating it")
        cursor.execute(create_table_statement)
        logger.info(cursor.fetchall())
        logger.info(f"Table '{GLUE_TABLE_NAME}' created in database '{GLUE_DATABASE_NAME}'")
    else:
        if FORCE_TABLE_CREATION:
            current_utc_time = datetime.datetime.now(datetime.UTC)
            formatted_time = current_utc_time.strftime('%Y%m%d_%H%M%S%f')
            base_table_name = f'{GLUE_DATABASE_NAME}.{GLUE_TABLE_NAME}'
            backup_table_name = f'{GLUE_DATABASE_NAME}.{GLUE_TABLE_NAME}_{formatted_time}'
            # we first backup only if we force table re-creation
            cursor.execute(f'ALTER TABLE {base_table_name} RENAME TO {backup_table_name}')
            logger.info(f'{base_table_name} backed up to {backup_table_name}')
            # we then re-create the table to the final location
            cursor.execute(create_table_statement)
            logger.info(cursor.fetchall())
            logger.info(f"Table '{GLUE_TABLE_NAME}' created in database '{GLUE_DATABASE_NAME}'")
