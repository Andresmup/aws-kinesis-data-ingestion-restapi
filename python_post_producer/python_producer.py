import requests
import json
import base64
import random
from faker import Faker

fake = Faker()

#Get size
def getSize():
	sizes=["XXS", "XS", "S", "M", "L", "XL", "XXL", "XXXL"]
	random_size = random.randint(0, 7)
	size=sizes[random_size]
	return size

#Get payment type
def getPaymentType():
	types=["debit_card", "credit_card", "cash", "coupon", "wallet"]
	random_type = random.randint(0, 4)
	payment_type=types[random_type]
	return payment_type

#Get customer id
def getCustomer():
	customer_pool=[
        'user3542', 'user7668', 'user0013', 'user7361', 'user0300', 'user5277', 
        'user2347', 'user5194', 'user0248', 'user2580', 'user5700', 'user3134', 
        'user2237', 'user5347', 'user9667', 'user3130', 'user4158', 'user8913', 
        'user0170', 'user5571', 'user9119', 'user0805', 'user6817', 'user1665', 
        'user4503', 'user8682', 'user1615', 'user6191', 'user9074', 'user5242']
	random_customer = random.randint(0, 29)
	customer_id=customer_pool[random_customer]
	return customer_id
    
#Order counter
i = 0

while True:
    i=int(i)+1

    print("Number of order " + str(i))

    # Generate fake data
    order_date = fake.date_time_this_month().isoformat() + "Z"
    street = fake.street_address()
    city = fake.city()
    state = fake.state()
    zip_code = fake.zipcode()
    country = fake.country()
    product_names = [fake.word() for _ in range(2)]
    product_colors = [fake.color_name() for _ in range(2)]
    product_sizes = [fake.random_letter() for _ in range(2)]

    # Order data structure
    order_data = {
        "customer_id": getCustomer(),
        "order_id": "o"+str(random.randint(0, 99999)).zfill(5),
        "order_date": order_date,
        "status": "pending",
        "shipping_address": {
            "street": street,
            "city": city,
            "state": state,
            "zip": zip_code,
            "country": country
        },
        "purchaise_details": {
            "payment_type": getPaymentType(),
            "amount": round(random.uniform(10, 100), 2),
            "currency": "USD",
            "instalments": random.randint(1, 13)
        },
        "product_details": [
            {
                "product_id": "p"+str(random.randint(0, 999999)).zfill(5),
                "name": product_names[0],
                "quantity": random.randint(1, 5),
                "item_details": {
                    "color": product_colors[0],
                    "size": getSize()
                }
            },
            {
                "product_id": "p"+str(random.randint(0, 999999)).zfill(5),
                "name": product_names[1],
                "quantity": random.randint(1, 5),
                "item_details": {
                    "color": product_colors[1],
                    "size": getSize()
                }
            }
        ]
    }

    # Convert to json order data
    json_order_data = json.dumps(order_data)
    print("order_data", json_order_data, "\n") #Print json order data

    # Encode data
    base64_order_data= base64.b64encode(json_order_data.encode()).decode()

    #Body request
    body = {
        "StreamName": "ingestion-dev",
        "PartitionKey": "test-partition-01",
        "Data": base64_order_data

    }
    print("body", body, "\n") #Print json body

    # Deploy api gateway endpoint
    endpoint = "https://ndr4bpix52.execute-api.us-east-1.amazonaws.com/apiv1"

    # Stage
    stage = "/orders"

    # Url requst post
    url = endpoint+stage


    # Request headers
    headers = {
        "Content-Type": "application/json"
    }

    # Make POST request
    response = requests.post(url, headers=headers, data=json.dumps(body))

    # Print response
    print("Total ingested:"+str(i) + ",HTTPStatusCode:" + str(response.status_code))
    print(response.json())
    print("--------------------")