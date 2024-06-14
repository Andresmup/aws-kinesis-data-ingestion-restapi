from decimal import Decimal
import base64
import json
import boto3
import os

# Updated from github action

def lambda_handler(event, context):
    #Get region
    my_region = os.environ['AWS_REGION']

    #Load dynamodb table from enviroment variable
    dynamoDBTableName = os.environ['dynamoDBTableName']

    #dynamodb client
    dynamodb = boto3.resource('dynamodb', region_name=my_region)
    table = dynamodb.Table(dynamoDBTableName) #Associate with table

    #Parse event to get records
    raw_kinesis_records = event['Records']

    #Loop through records
    for record in raw_kinesis_records:

        #Parse data from the body and decode
        payload=json.loads(base64.b64decode(record["kinesis"]["data"]).decode("UTF-8"))

        #Print data
        #print("Decoded payload: " + str(payload))

        #Get records for dynamodb 
        table_raw = {
            "customer_id": payload["customer_id"],
            "order_id": payload["order_id"],
            "order_date": payload["order_date"],
            "status": payload["status"],
            "shipping_address": payload["shipping_address"],
            "product_details": payload["product_details"]
        }

        #Print item
        #print("Item: " + str(table_raw))

        #Data for table
        ddb_data = json.loads(json.dumps(table_raw), parse_float=Decimal)
        
        response = table.put_item(Item=ddb_data)
        print ('response' ,response)

