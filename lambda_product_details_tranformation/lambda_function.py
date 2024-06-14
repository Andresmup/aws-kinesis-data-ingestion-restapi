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

        # Create partition keys based on the order_date
        event_timestamp = datetime.datetime.fromisoformat(json_payload['order_date'].rstrip("Z"))
        partition_keys = {"year": event_timestamp.strftime('%Y'),
                          "month": event_timestamp.strftime('%m'),
                          "day": event_timestamp.strftime('%d'),
                          "hour": event_timestamp.strftime('%H')}

        # Track if we used the original recordId
        original_record_id_used = False

        # Process each product detail
        for index, product_detail in enumerate(json_payload['product_details']):
            # Data to be sent through Firehose
            data = {
                "product_id": product_detail['product_id'],
                "order_id": json_payload['order_id'],
                "name": product_detail['name'],
                "quantity": product_detail['quantity'],
                "color": product_detail['item_details']['color'],
                "size": product_detail['item_details']['size']
            }
        
            # Convert the payload to JSON and then to Base64
            encoded_data = base64.b64encode(json.dumps(data).encode('utf-8')).decode('utf-8')

            # Use the original recordId for the first product, then generate unique ones
            if not original_record_id_used:
                unique_record_id = record['recordId']
                original_record_id_used = True
            else:
                unique_record_id = f"{record['recordId']}_{index}"

            # Create Firehose output object and add the modified payload and record ID.
            firehose_record_output = {
                'recordId': unique_record_id,
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

