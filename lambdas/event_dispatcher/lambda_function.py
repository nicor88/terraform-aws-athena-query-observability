import datetime
import json
import logging
import os

import boto3
import tenacity

logger = logging.getLogger()
logger.setLevel(logging.INFO)

athena = boto3.client('athena')

firehose = boto3.client('firehose')

FIREHOSE_DELIVERY_STREAM = os.environ.get('FIREHOSE_DELIVERY_STREAM')


def handler(event, context):
    logger.debug('Boto3 version: {}'.format(boto3.__version__))
    logger.info('Event: {}'.format(event))

    detail = event.get('detail', {})
    current_state = detail.get('currentState')
    workgroup = detail.get('workgroupName')
    logger.info('Current state: {}'.format(current_state))
    query_execution_id = detail.get('queryExecutionId')

    if query_execution_id and current_state != 'QUEUED':
        query_execution = athena.get_query_execution(QueryExecutionId=query_execution_id)
        logger.info('Query execution: {}'.format(query_execution))

    event_time = event.get('time')
    logger.info('Parsed event time: {}'.format(event_time))

    parsed_event_time = datetime.datetime.fromisoformat(event_time)

    firehose_event = {
        'event_id': event.get('id'),
        'event_date': str(parsed_event_time.date()),
        'event_timestamp': str(parsed_event_time),
        # there is an issue in timestamp serialization, we use string for now
        'query_execution_id': query_execution_id,
        'workgroup_name': workgroup,
        'current_state': current_state,
        'previous_state': detail.get('previousState'),
        'statement_type': detail.get('statementType'),
        'substatement_type': None,

        # initialize empty properties
        'query': None,
        'query_statistics': {},
        'submission_timestamp': None,
        'completion_timestamp': None,
        'engine_version': {},

    }

    # consider to add a retry logic here

    if query_execution_id and current_state != 'QUEUED':
        query_execution = athena.get_query_execution(QueryExecutionId=query_execution_id).get('QueryExecution', {})
        logger.info('Query execution: {}'.format(query_execution))

        firehose_event['query'] = query_execution.get('Query')
        firehose_event['query_statistics'] = query_execution.get('Statistics', {})
        firehose_event['engine_version'] = query_execution.get('EngineVersion', {})
        execution_status = query_execution.get('Status', {})
        firehose_event['substatement_type'] = query_execution.get('SubstatementType')

        sumbission_time = execution_status.get('SubmissionDateTime')

        if sumbission_time:
            firehose_event['submission_timestamp'] = str(sumbission_time)

        completion_time = execution_status.get('CompletionDateTime')

        if completion_time:
            firehose_event['completion_timestamp'] = str(completion_time)

    logger.info('Firehose event: {}'.format(firehose_event))

    response = firehose.put_record(
        DeliveryStreamName=FIREHOSE_DELIVERY_STREAM,
        Record={
            'Data': json.dumps(firehose_event, default=str)
        }
    )

    logger.info('Firehose response: {}'.format(response))

    return firehose_event
