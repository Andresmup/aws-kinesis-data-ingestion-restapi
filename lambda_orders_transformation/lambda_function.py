import base64
import json
import datetime

# Updated from github action

def lambda_handler(event, context):
    # Create return value.
    firehose_records_output = {'records': []}

    # Print event
    print(event)

    # Process each record in the event
    for record in event['records']:
        # Get payload
        payload = base64.b64decode(record['data']).decode('utf-8')
        json_payload = json.loads(payload)
        
        # Print payload
        print(json_payload)

        # Create Firehose output object and add the modified payload and record ID.
        event_timestamp = datetime.datetime.fromisoformat(json_payload['order_date'].rstrip("Z"))
        partition_keys = {"customer_id": json_payload["customer_id"],
                          "year": event_timestamp.strftime('%Y'),
                          "month": event_timestamp.strftime('%m'),
                          "day": event_timestamp.strftime('%d'),
                          "hour": event_timestamp.strftime('%H')}

        #Conversion
        order_date = event_timestamp.date().isoformat()

        # Data to send through Firehose
        data = {
                "customer_id": json_payload['customer_id'],
                "order_id": json_payload['order_id'],
                "order_date": order_date,
                "status": json_payload['status']
        }
        
        # Convert the payload to JSON and then to Base64
        encoded_data = base64.b64encode(json.dumps(data).encode('utf-8')).decode('utf-8')

        # Create Firehose output object and add the modified payload and record ID.
        firehose_record_output = {
            'recordId': record['recordId'],
            'result': 'Ok',
            'data': encoded_data,
            'metadata': {'partitionKeys': partition_keys}
        }

        # Print firehose_record_output
        print(firehose_record_output)

        firehose_records_output['records'].append(firehose_record_output)

    print('Successfully processed {} records.'.format(len(event['records'])))

    # Return firehose_records_output "filtered and processed data"
    print('Output records send back to firehose', firehose_records_output)
    return firehose_records_output