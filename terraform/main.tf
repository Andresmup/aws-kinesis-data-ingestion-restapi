terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.52.0"
    }
  }
}

provider "aws" {
  # Configuration options
}

#KINESIS RESOURCE
#################################################################################################################

resource "aws_kinesis_stream" "kinesis_data_stream" {
  name = "${var.app_name}-${var.app_environment}"

  shard_level_metrics = [
    "IncomingBytes",
    "OutgoingBytes",
  ]

  stream_mode_details {
    stream_mode = "ON_DEMAND"
  }

}

#API GATEWAY IAM
#################################################################################################################

resource "aws_iam_policy" "kinesis_put_record_policy" {
  name = "producer-kinesis-${var.app_name}-${var.app_environment}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowPutRecordTestStreamConsole",
        "Effect" : "Allow",
        "Action" : "kinesis:PutRecord",
        "Resource" : "${aws_kinesis_stream.kinesis_data_stream.arn}"
      }
    ]
  })
}

resource "aws_iam_role" "api_gateway_role" {
  name = "api-gateway-${var.app_name}-${var.app_environment}-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowAssumeApiGateway",
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "apigateway.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })

}

resource "aws_iam_role_policy_attachment" "api_gateway_attach" {
  role       = aws_iam_role.api_gateway_role.name
  policy_arn = aws_iam_policy.kinesis_put_record_policy.arn
}

#API GATEWAY RESOURCE
#################################################################################################################

resource "aws_api_gateway_rest_api" "rest_api_gateway" {
  name        = "rest-api-gateway-${var.app_name}-${var.app_environment}"
  description = "Rest API for data ingestion"
  endpoint_configuration {
    types = ["REGIONAL"]
  }
}

resource "aws_api_gateway_resource" "data_resource" {
  rest_api_id = aws_api_gateway_rest_api.rest_api_gateway.id
  parent_id   = aws_api_gateway_rest_api.rest_api_gateway.root_resource_id
  path_part   = var.endpoint_name
}

resource "aws_api_gateway_method" "data_post" {
  rest_api_id   = aws_api_gateway_rest_api.rest_api_gateway.id
  resource_id   = aws_api_gateway_resource.data_resource.id
  http_method   = "POST"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "kinesis_integration" {
  rest_api_id             = aws_api_gateway_rest_api.rest_api_gateway.id
  resource_id             = aws_api_gateway_resource.data_resource.id
  http_method             = aws_api_gateway_method.data_post.http_method
  integration_http_method = "POST"
  type                    = "AWS"
  uri                     = "arn:aws:apigateway:us-east-1:kinesis:action/PutRecord"

  credentials = aws_iam_role.api_gateway_role.arn

  request_templates = {
    "application/json" = <<EOF
#set($inputRoot = $input.path('$'))
{
  "StreamName": "$inputRoot.StreamName",
  "PartitionKey": "$inputRoot.PartitionKey",
  "Data": "$inputRoot.Data"
}
EOF
  }
}

resource "aws_api_gateway_method_response" "method_response" {
  rest_api_id = aws_api_gateway_rest_api.rest_api_gateway.id
  resource_id = aws_api_gateway_resource.data_resource.id
  http_method = aws_api_gateway_method.data_post.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}

resource "aws_api_gateway_integration_response" "integration_response" {
  rest_api_id = aws_api_gateway_rest_api.rest_api_gateway.id
  resource_id = aws_api_gateway_resource.data_resource.id
  http_method = aws_api_gateway_method.data_post.http_method
  status_code = "200"

  response_templates = {
    "application/json" = ""
  }

  depends_on = [
    aws_api_gateway_integration.kinesis_integration
  ]
}

resource "aws_api_gateway_deployment" "deployment" {
  depends_on = [
    aws_api_gateway_method.data_post,
    aws_api_gateway_integration.kinesis_integration,
    aws_api_gateway_method_response.method_response,
    aws_api_gateway_integration_response.integration_response,
  ]

  rest_api_id = aws_api_gateway_rest_api.rest_api_gateway.id
  stage_name  = var.stage_name
}

# Output the deploy URL of the API Gateway
output "api_gateway_url" {
  description = "API Gateway deploy URL"
  value       = aws_api_gateway_deployment.deployment.invoke_url
}

#LAMBDA CONSUMER IAM
#################################################################################################################

resource "aws_iam_policy" "lambda_cloudwatch_policy" {
  name = "lambda-logs-cloudwatch-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "*"
      }
    ]
  })
}

#LAMBDA CONSUMER IAM
#################################################################################################################

resource "aws_iam_policy" "kinesis_get_records_policy" {
  name = "consumer-kinesis-${var.app_name}-${var.app_environment}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "GetRecordsKinesis",
        "Effect" : "Allow",
        "Action" : [
          "kinesis:SubscribeToShard",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListShards",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:DescribeStream"
        ],
        "Resource" : "${aws_kinesis_stream.kinesis_data_stream.arn}"
      },
      {
        "Sid" : "ListStreamsKinesis",
        "Effect" : "Allow",
        "Action" : "kinesis:ListStreams",
        "Resource" : "*"
      }
    ]
  })
}

#LAMBDA CONSUMER IAM
#################################################################################################################

resource "aws_iam_role" "lambda_kinesis_consumer_role" {
  name = "lambda-kinesis-consumer-${var.app_name}-${var.app_environment}-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

#Attach kinesis_get_records_policy
resource "aws_iam_role_policy_attachment" "attach-lambda-consumer-custom-managed-kinesis-policy" {
  role       = aws_iam_role.lambda_kinesis_consumer_role.name
  policy_arn = aws_iam_policy.kinesis_get_records_policy.arn
}

#Attach lambda_transformation_role
resource "aws_iam_role_policy_attachment" "attach-lambda-consumer-custom-managed-cloudwatch-policy" {
  role       = aws_iam_role.lambda_kinesis_consumer_role.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}

#LAMBDA CONSUMER RESOURCE
#################################################################################################################

# Define the Lambda function consumer from kinesis data stream
resource "aws_lambda_function" "lambda_kinesis_consumer" {
  function_name = "lambda-function-kinesis-consumer-${var.app_name}-${var.app_environment}"
  role          = aws_iam_role.lambda_kinesis_consumer_role.arn
  handler       = var.lambda_handler
  runtime       = var.python_runtime
  timeout       = 60
  filename      = "deploy_consumer.zip"

  environment {
    variables = {
      dynamoDBTableName = "${aws_dynamodb_table.dynamodb_table.name}" #TO DO
    }
  }
}

#Define kinesis trigger for lambda function
resource "aws_lambda_event_source_mapping" "example" {
  event_source_arn                   = aws_kinesis_stream.kinesis_data_stream.arn
  function_name                      = aws_lambda_function.lambda_kinesis_consumer.arn
  starting_position                  = "LATEST"
  batch_size                         = 1000
  maximum_batching_window_in_seconds = 120
  maximum_retry_attempts             = 2
  tumbling_window_in_seconds         = 30
}

#LAMBDA CONSUMER IAM
#################################################################################################################

resource "aws_iam_policy" "lambda_consumer_update_code_policy" {
  name = "lambda-consumer-update-code-${var.app_name}-${var.app_environment}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "UpdateCodeLambdaConsumer",
        "Effect" : "Allow",
        "Action" : "lambda:UpdateFunctionCode",
        "Resource" : [
          "${aws_lambda_function.lambda_kinesis_consumer.arn}",
          "${aws_lambda_function.lambda_orders_firehose_transformation.arn}",
          "${aws_lambda_function.lambda_product_details_firehose_transformation.arn}",
          "${aws_lambda_function.lambda_shipping_addresses_firehose_transformation.arn}",
          "${aws_lambda_function.lambda_purchase_details_firehose_transformation.arn}"
        ]
      }
    ]
  })
}

#Create role github action machine update lambda consumer code 
resource "aws_iam_role" "github_action_lambda_consumer_role" {
  name = "github-action-lambda-consumer-${var.app_name}-${var.app_environment}-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Federated" : "arn:aws:iam::${var.account_id}:oidc-provider/token.actions.githubusercontent.com"
        },
        "Action" : "sts:AssumeRoleWithWebIdentity",
        "Condition" : {
          "StringEquals" : {
            "token.actions.githubusercontent.com:aud" : "sts.amazonaws.com"
          },
          "StringLike" : {
            "token.actions.githubusercontent.com:sub" : "repo:${var.github_org}/${var.repository_name}:*"
          }
        }
      }
    ]
  })
}

#Attach lambda_consumer_update_code_policy
resource "aws_iam_role_policy_attachment" "attach-github-action-policy" {
  role       = aws_iam_role.github_action_lambda_consumer_role.name
  policy_arn = aws_iam_policy.lambda_consumer_update_code_policy.arn
}

# Output the ARN of Github Action role
output "github_action_lambda_consumer_role_arn" {
  description = "Github action machine lambda consumer role ARN"
  value       = aws_iam_role.github_action_lambda_consumer_role.arn
}

#DYNAMODB RESOURCE
#################################################################################################################

resource "aws_dynamodb_table" "dynamodb_table" {
  name           = "orders-${var.app_name}-${var.app_environment}-table"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key       = "customer_id"
  range_key      = "order_id"

  attribute {
    name = "customer_id"
    type = "S"
  }

  attribute {
    name = "order_id"
    type = "S"
  }

  ttl {
    attribute_name = "TimeToExist"
    enabled        = false
  }

}

#DYNAMODB IAM
#################################################################################################################

resource "aws_iam_policy" "dynamodb_put_item_policy" {
  name = "put-item-dynamodb-${var.app_name}-${var.app_environment}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "PutItemDynamoDBTable",
        "Effect" : "Allow",
        "Action" : "dynamodb:PutItem",
        "Resource" : "${aws_dynamodb_table.dynamodb_table.arn}"
      }
    ]
  })

}

resource "aws_iam_role_policy_attachment" "attach-lambda-consumer-custom-managed-dynamodb-policy" {
  role       = aws_iam_role.lambda_kinesis_consumer_role.name
  policy_arn = aws_iam_policy.dynamodb_put_item_policy.arn
}

#S3 BUCKET RESOURCE
#################################################################################################################

resource "aws_s3_bucket" "bucket_data_storage" {
  bucket = "data-storage-${var.app_name}-${var.app_environment}"

  force_destroy = true
  lifecycle {
    prevent_destroy = false
  }
}

#S3 BUCKET IAM
#################################################################################################################

resource "aws_iam_policy" "bucket_access_policy" {
  name = "access-bucket-data-storage-${var.app_name}-${var.app_environment}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowAccessS3Bucket",
        "Effect" : "Allow",
        "Action" : [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ],
        "Resource" : [
          "${aws_s3_bucket.bucket_data_storage.arn}",
          "${aws_s3_bucket.bucket_data_storage.arn}/*"
        ]
      }
    ]
  })

}

#LAMBDA TRANSFORMATION IAM
#################################################################################################################

resource "aws_iam_role" "lambda_firehose_transformation_role" {
  name = "lambda-firehose-transformation-${var.app_name}-${var.app_environment}-role"

  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Principal" : {
          "Service" : "lambda.amazonaws.com"
        },
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

#Attach lambda_cloudwatch_policy
resource "aws_iam_role_policy_attachment" "attach-lambda-firehose-custom-managed-cloudwatch-policy" {
  role       = aws_iam_role.lambda_firehose_transformation_role.name
  policy_arn = aws_iam_policy.lambda_cloudwatch_policy.arn
}

#FIREHOSE BASE IAM
#################################################################################################################

resource "aws_iam_policy" "firehose_base_requirement_multi_statement_policy" {
  name = "firehose_base_requirement_multi_statement_policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowAccessS3Bucket",
        "Effect" : "Allow",
        "Action" : [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ],
        "Resource" : [
          "${aws_s3_bucket.bucket_data_storage.arn}",
          "${aws_s3_bucket.bucket_data_storage.arn}/*"
        ]
      },
      {
        "Sid" : "CloudwatchAccess"
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        "Resource" : "*"
      },
      {
        "Sid" : "GetRecordsKinesis",
        "Effect" : "Allow",
        "Action" : [
          "kinesis:SubscribeToShard",
          "kinesis:DescribeStreamSummary",
          "kinesis:ListShards",
          "kinesis:GetShardIterator",
          "kinesis:GetRecords",
          "kinesis:DescribeStream"
        ],
        "Resource" : "${aws_kinesis_stream.kinesis_data_stream.arn}"
      },
      {
        "Sid" : "ListStreamsKinesis",
        "Effect" : "Allow",
        "Action" : "kinesis:ListStreams",
        "Resource" : "*"
      },
      {
        "Sid" : "AllowGlueSchemaAccess",
        "Effect" : "Allow",
        "Action" : [
          "glue:GetTable",
          "glue:GetTableVersion",
          "glue:GetTableVersions",
          "glue:GetSchema",
          "glue:GetSchemaVersion",
          "glue:GetSchemaVersionsDiff"
        ],
        "Resource" : "*"
      }
    ]
  })
}

#FIREHOSE BASE IAM
#################################################################################################################

resource "aws_iam_role" "kinesis_firehose_base_role" {
  name = "kinesis-firehose-base-${var.app_name}-${var.app_environment}-role"

  # Terraform's "jsonencode" function converts a
  # Terraform expression result to valid JSON syntax.
  assume_role_policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Principal" : {
          "Service" : [
            "firehose.amazonaws.com"
          ]
        },
        "Effect" : "Allow",
        "Action" : "sts:AssumeRole"
      }
    ]
  })
}

#FIREHOSE BASE VARIABLE
#################################################################################################################

data "aws_iam_role" "firehose_base_role" {
  name = aws_iam_role.kinesis_firehose_base_role.name
}


#LAMBDA ORDERS TRANSFORMATION RESOURCE
#################################################################################################################

# Define the Lambda function for orders transformation
resource "aws_lambda_function" "lambda_orders_firehose_transformation" {
  function_name = "lambda-orders-transformation-${var.app_name}-${var.app_environment}"
  role          = aws_iam_role.lambda_firehose_transformation_role.arn
  handler       = var.lambda_handler
  runtime       = var.python_runtime
  timeout       = 60
  filename      = "deploy_orders_transformation.zip"

}

#FIREHOSE ORDERS IAM
#################################################################################################################

resource "aws_iam_policy" "firehose_lambda_orders_policy" {
  name = "firehose-lambda-orders-${var.app_name}-${var.app_environment}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "lambda:InvokeFunction",
          "lambda:GetFunctionConfiguration"
        ],
        "Resource" : "${aws_lambda_function.lambda_orders_firehose_transformation.arn}:*"
      }
    ]
  })
}

resource "aws_iam_policy" "firehose_put_orders_policy" {
  name = "firehose-put-orders-${var.app_name}-${var.app_environment}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ],
        "Resource" : [
          "${aws_kinesis_firehose_delivery_stream.firehose_orders.arn}"
        ]
      }
    ]
  })
}

#FIREHOSE ORDERS IAM
#################################################################################################################

#Create role from base role
resource "aws_iam_role" "kinesis_firehose_orders_role" {
  name               = "firehose-orders-${var.app_name}-${var.app_environment}-role"
  assume_role_policy = data.aws_iam_role.firehose_base_role.assume_role_policy
}

#Attach base policies
resource "aws_iam_role_policy_attachment" "attach-firehose-orders-base-policies" {
  role       = aws_iam_role.kinesis_firehose_orders_role.name
  policy_arn = aws_iam_policy.firehose_base_requirement_multi_statement_policy.arn
}

#Attach put policy
resource "aws_iam_role_policy_attachment" "attach-firehose-orders-put-policies" {
  role       = aws_iam_role.kinesis_firehose_orders_role.name
  policy_arn = aws_iam_policy.firehose_put_orders_policy.arn
}

#Attach firehose_lambda_orders_policy
resource "aws_iam_role_policy_attachment" "attach-firehose-orders-lambda-policy" {
  role       = aws_iam_role.kinesis_firehose_orders_role.name
  policy_arn = aws_iam_policy.firehose_lambda_orders_policy.arn
}

#FIREHOSE ORDERS RESOURCE
#################################################################################################################

resource "aws_kinesis_firehose_delivery_stream" "firehose_orders" {
  name        = "firehose-orders-${var.app_name}-${var.app_environment}"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.kinesis_data_stream.arn
    role_arn           = aws_iam_role.kinesis_firehose_orders_role.arn
  }


  extended_s3_configuration {
    role_arn   = aws_iam_role.kinesis_firehose_orders_role.arn
    bucket_arn = aws_s3_bucket.bucket_data_storage.arn

    buffering_size = 128

    dynamic_partitioning_configuration {
      enabled = true
    }

    # Prefix using partitionKeys from Lambda metadata
    prefix              = "orders/customer_id=!{partitionKeyFromLambda:customer_id}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/"

    #Processing
    processing_configuration {
      enabled = true

      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.lambda_orders_firehose_transformation.arn}:$LATEST"
        }
      }

      processors {
        type = "AppendDelimiterToRecord"
      }
    }

    data_format_conversion_configuration {
      input_format_configuration {
        deserializer {
          hive_json_ser_de {

          }
        }
      }

      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression = var.parquet_compression_format
          }
        }
      }

      schema_configuration {
        database_name = aws_glue_catalog_database.catalog_database.name
        role_arn      = aws_iam_role.kinesis_firehose_orders_role.arn
        table_name    = aws_glue_catalog_table.aws_glue_orders_table.name
      }
    }
  }
}

#GLUE DATABASE RESOURCE
#################################################################################################################

resource "aws_glue_catalog_database" "catalog_database" {
  name = "catalog-${var.app_name}-${var.app_environment}-database"
}

#GLUE TABLE ORDERS RESOURCE
#################################################################################################################

resource "aws_glue_catalog_table" "aws_glue_orders_table" {
  name          = "orders-${var.app_name}-${var.app_environment}-table"
  database_name = aws_glue_catalog_database.catalog_database.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL              = "TRUE"
    "parquet.compression" = "${var.parquet_compression_format}"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.bucket_data_storage.id}/orders/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"

      parameters = {
        "serialization.format" = 1
      }
    }

    columns {
      name = "customer_id"
      type = "string"
    }

    columns {
      name = "order_id"
      type = "string"
    }

    columns {
      name = "order_date"
      type = "date"
    }

    columns {
      name = "status"
      type = "string"
    }
  }

}

#LAMBDA PRODUCT DETAILS TRANSFORMATION RESOURCE
#################################################################################################################

# Define the Lambda function for product details transformation
resource "aws_lambda_function" "lambda_product_details_firehose_transformation" {
  function_name = "lambda-product-details-transformation-${var.app_name}-${var.app_environment}"
  role          = aws_iam_role.lambda_firehose_transformation_role.arn
  handler       = var.lambda_handler
  runtime       = var.python_runtime
  timeout       = 60
  filename      = "deploy_product_details_transformation.zip"

}

#FIREHOSE PRODUCT DETAILS IAM
#################################################################################################################

resource "aws_iam_policy" "firehose_lambda_product_details_policy" {
  name = "firehose-lambda-product-details-${var.app_name}-${var.app_environment}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "lambda:InvokeFunction",
          "lambda:GetFunctionConfiguration"
        ],
        "Resource" : "${aws_lambda_function.lambda_product_details_firehose_transformation.arn}:*"
      }
    ]
  })
}

resource "aws_iam_policy" "firehose_put_product_detail_policy" {
  name = "firehose-put-product-detail-${var.app_name}-${var.app_environment}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ],
        "Resource" : [
          "${aws_kinesis_firehose_delivery_stream.firehose_product_details.arn}"
        ]
      }
    ]
  })
}

#FIREHOSE PRODUCT DETAILS IAM
#################################################################################################################

#Create role from base role
resource "aws_iam_role" "kinesis_firehose_product_details_role" {
  name               = "firehose-product-details-${var.app_name}-${var.app_environment}-role"
  assume_role_policy = data.aws_iam_role.firehose_base_role.assume_role_policy
}

#Attach base policies
resource "aws_iam_role_policy_attachment" "attach-firehose-product-details-base-policies" {
  role       = aws_iam_role.kinesis_firehose_product_details_role.name
  policy_arn = aws_iam_policy.firehose_base_requirement_multi_statement_policy.arn
}

#Attach put policy
resource "aws_iam_role_policy_attachment" "attach-firehose-product-details-put-policies" {
  role       = aws_iam_role.kinesis_firehose_product_details_role.name
  policy_arn = aws_iam_policy.firehose_put_product_detail_policy.arn
}

#Attach firehose_lambda_product_details_policy
resource "aws_iam_role_policy_attachment" "attach-firehose-product-details-lambda-policy" {
  role       = aws_iam_role.kinesis_firehose_product_details_role.name
  policy_arn = aws_iam_policy.firehose_lambda_product_details_policy.arn
}

#FIREHOSE PRODUCT DETAILS RESOURCE
#################################################################################################################

resource "aws_kinesis_firehose_delivery_stream" "firehose_product_details" {
  name        = "firehose-product-details-${var.app_name}-${var.app_environment}"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.kinesis_data_stream.arn
    role_arn           = aws_iam_role.kinesis_firehose_orders_role.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.kinesis_firehose_product_details_role.arn
    bucket_arn = aws_s3_bucket.bucket_data_storage.arn

    buffering_size = 128

    dynamic_partitioning_configuration {
      enabled = true
    }

    # Prefix using partitionKeys from Lambda metadata
    prefix              = "product_details/year=!{partitionKeyFromLambda:year}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/"

    #Processing
    processing_configuration {
      enabled = true

      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.lambda_product_details_firehose_transformation.arn}:$LATEST"
        }
      }

      processors {
        type = "AppendDelimiterToRecord"
      }
    }

    data_format_conversion_configuration {
      input_format_configuration {
        deserializer {
          hive_json_ser_de {

          }
        }
      }

      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression = var.parquet_compression_format
          }
        }
      }

      schema_configuration {
        database_name = aws_glue_catalog_database.catalog_database.name
        role_arn      = aws_iam_role.kinesis_firehose_shipping_addresses_role.arn
        table_name    = aws_glue_catalog_table.aws_glue_product_details_table.name
      }
    }
  }
}

#GLUE TABLE PRODUCT DETAILS RESOURCE
#################################################################################################################

resource "aws_glue_catalog_table" "aws_glue_product_details_table" {
  name          = "product-details-${var.app_name}-${var.app_environment}-table"
  database_name = aws_glue_catalog_database.catalog_database.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL              = "TRUE"
    "parquet.compression" = "${var.parquet_compression_format}"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.bucket_data_storage.id}/product_details/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"

      parameters = {
        "serialization.format" = 1
      }
    }

    columns {
      name = "product_id"
      type = "string"
    }

    columns {
      name = "order_id"
      type = "string"
    }

    columns {
      name = "name"
      type = "string"
    }

    columns {
      name = "quantity"
      type = "int"
    }

    columns {
      name = "color"
      type = "string"
    }

    columns {
      name = "size"
      type = "string"
    }
  }

}


#LAMBDA SHIPPING ADDRESSES TRANSFORMATION RESOURCE
#################################################################################################################

# Define the Lambda function for shipping addresses transformation
resource "aws_lambda_function" "lambda_shipping_addresses_firehose_transformation" {
  function_name = "lambda-shipping-addresses-transformation-${var.app_name}-${var.app_environment}"
  role          = aws_iam_role.lambda_firehose_transformation_role.arn
  handler       = var.lambda_handler
  runtime       = var.python_runtime
  timeout       = 60
  filename      = "deploy_shipping_addresses_transformation.zip"

}

#FIREHOSE SHIPPING ADDRESSES IAM
#################################################################################################################

resource "aws_iam_policy" "firehose_lambda_shipping_addresses_policy" {
  name = "firehose-lambda-shipping-addresses-${var.app_name}-${var.app_environment}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "lambda:InvokeFunction",
          "lambda:GetFunctionConfiguration"
        ],
        "Resource" : "${aws_lambda_function.lambda_shipping_addresses_firehose_transformation.arn}:*"
      }
    ]
  })
}

resource "aws_iam_policy" "firehose_put_shipping_addresses_policy" {
  name = "firehose-put-shipping-addresses-${var.app_name}-${var.app_environment}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ],
        "Resource" : [
          "${aws_kinesis_firehose_delivery_stream.firehose_shipping_addresses.arn}"
        ]
      }
    ]
  })
}

#FIREHOSE SHIPPING ADDRESSES IAM
#################################################################################################################

#Create role from base role
resource "aws_iam_role" "kinesis_firehose_shipping_addresses_role" {
  name               = "firehose-shipping-addresses-${var.app_name}-${var.app_environment}-role"
  assume_role_policy = data.aws_iam_role.firehose_base_role.assume_role_policy
}

#Attach base policies
resource "aws_iam_role_policy_attachment" "attach-firehose-shipping-addresses-base-policies" {
  role       = aws_iam_role.kinesis_firehose_shipping_addresses_role.name
  policy_arn = aws_iam_policy.firehose_base_requirement_multi_statement_policy.arn
}

#Attach put policy
resource "aws_iam_role_policy_attachment" "attach-firehose-shipping-addresses-put-policies" {
  role       = aws_iam_role.kinesis_firehose_shipping_addresses_role.name
  policy_arn = aws_iam_policy.firehose_put_shipping_addresses_policy.arn
}

#Attach firehose_lambda_shipping_addresses_policy
resource "aws_iam_role_policy_attachment" "attach-firehose-shipping-addresses-lambda-policy" {
  role       = aws_iam_role.kinesis_firehose_shipping_addresses_role.name
  policy_arn = aws_iam_policy.firehose_lambda_shipping_addresses_policy.arn
}

#FIREHOSE SHIPPING ADDRESSES RESOURCE
#################################################################################################################

resource "aws_kinesis_firehose_delivery_stream" "firehose_shipping_addresses" {
  name        = "firehose-shipping-addresses-${var.app_name}-${var.app_environment}"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.kinesis_data_stream.arn
    role_arn           = aws_iam_role.kinesis_firehose_orders_role.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.kinesis_firehose_shipping_addresses_role.arn
    bucket_arn = aws_s3_bucket.bucket_data_storage.arn

    buffering_size = 128

    dynamic_partitioning_configuration {
      enabled = true
    }

    # Prefix using partitionKeys from Lambda metadata
    prefix              = "shipping_addresses/country=!{partitionKeyFromLambda:country}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/"

    #Processing
    processing_configuration {
      enabled = true

      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.lambda_shipping_addresses_firehose_transformation.arn}:$LATEST"
        }
      }

      processors {
        type = "AppendDelimiterToRecord"
      }
    }

    data_format_conversion_configuration {
      input_format_configuration {
        deserializer {
          hive_json_ser_de {

          }
        }
      }

      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression = var.parquet_compression_format
          }
        }
      }

      schema_configuration {
        database_name = aws_glue_catalog_database.catalog_database.name
        role_arn      = aws_iam_role.kinesis_firehose_shipping_addresses_role.arn
        table_name    = aws_glue_catalog_table.aws_glue_shipping_addresses_table.name
      }
    }
  }
}

#GLUE TABLE SHIPPING ADDRESSES RESOURCE
#################################################################################################################

resource "aws_glue_catalog_table" "aws_glue_shipping_addresses_table" {
  name          = "shipping-addresses-${var.app_name}-${var.app_environment}-table"
  database_name = aws_glue_catalog_database.catalog_database.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL              = "TRUE"
    "parquet.compression" = "${var.parquet_compression_format}"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.bucket_data_storage.id}/shipping_addresses/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"

      parameters = {
        "serialization.format" = 1
      }
    }

    columns {
      name = "order_id"
      type = "string"
    }

    columns {
      name = "country"
      type = "string"
    }

    columns {
      name = "state"
      type = "string"
    }

    columns {
      name = "city"
      type = "string"
    }

    columns {
      name = "street"
      type = "string"
    }

    columns {
      name = "zip"
      type = "string"
    }
  }

}

#LAMBDA PURCHASE DETAILS TRANSFORMATION RESOURCE
#################################################################################################################

# Define the Lambda function for purchase details transformation
resource "aws_lambda_function" "lambda_purchase_details_firehose_transformation" {
  function_name = "lambda-purchase-details-transformation-${var.app_name}-${var.app_environment}"
  role          = aws_iam_role.lambda_firehose_transformation_role.arn
  handler       = var.lambda_handler
  runtime       = var.python_runtime
  timeout       = 60
  filename      = "deploy_purchase_details_transformation.zip"

}

#FIREHOSE PURCHASE DETAILS IAM
#################################################################################################################

resource "aws_iam_policy" "firehose_lambda_purchase_details_policy" {
  name = "firehose-lambda-purchase-details-${var.app_name}-${var.app_environment}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "lambda:InvokeFunction",
          "lambda:GetFunctionConfiguration"
        ],
        "Resource" : "${aws_lambda_function.lambda_purchase_details_firehose_transformation.arn}:*"
      }
    ]
  })
}

resource "aws_iam_policy" "firehose_put_purchase_details_policy" {
  name = "firehose-put-purchase-details-${var.app_name}-${var.app_environment}-policy"

  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Effect" : "Allow",
        "Action" : [
          "firehose:PutRecord",
          "firehose:PutRecordBatch"
        ],
        "Resource" : [
          "${aws_kinesis_firehose_delivery_stream.firehose_purchase_details.arn}"
        ]
      }
    ]
  })
}

#FIREHOSE PURCHASE DETAILS IAM
#################################################################################################################

#Create role from base role
resource "aws_iam_role" "kinesis_firehose_purchase_details_role" {
  name               = "firehose-purchase-details-${var.app_name}-${var.app_environment}-role"
  assume_role_policy = data.aws_iam_role.firehose_base_role.assume_role_policy
}

#Attach base policies
resource "aws_iam_role_policy_attachment" "attach-firehose-purchase-details-base-policies" {
  role       = aws_iam_role.kinesis_firehose_purchase_details_role.name
  policy_arn = aws_iam_policy.firehose_base_requirement_multi_statement_policy.arn
}

#Attach put policy
resource "aws_iam_role_policy_attachment" "attach-firehose-purchase-details-put-policies" {
  role       = aws_iam_role.kinesis_firehose_purchase_details_role.name
  policy_arn = aws_iam_policy.firehose_put_purchase_details_policy.arn
}

#Attach firehose_lambda_purchase_details_policy
resource "aws_iam_role_policy_attachment" "attach-firehose-purchase-details-lambda-policy" {
  role       = aws_iam_role.kinesis_firehose_purchase_details_role.name
  policy_arn = aws_iam_policy.firehose_lambda_purchase_details_policy.arn
}

#FIREHOSE PURCHASE DETAILS RESOURCE
#################################################################################################################

resource "aws_kinesis_firehose_delivery_stream" "firehose_purchase_details" {
  name        = "firehose-purchase-details-${var.app_name}-${var.app_environment}"
  destination = "extended_s3"

  kinesis_source_configuration {
    kinesis_stream_arn = aws_kinesis_stream.kinesis_data_stream.arn
    role_arn           = aws_iam_role.kinesis_firehose_orders_role.arn
  }

  extended_s3_configuration {
    role_arn   = aws_iam_role.kinesis_firehose_purchase_details_role.arn
    bucket_arn = aws_s3_bucket.bucket_data_storage.arn

    buffering_size = 128

    dynamic_partitioning_configuration {
      enabled = true
    }

    # Prefix using partitionKeys from Lambda metadata
    prefix              = "purchase_details/year=!{partitionKeyFromLambda:year}/month=!{partitionKeyFromLambda:month}/"
    error_output_prefix = "errors/!{firehose:error-output-type}/"

    #Processing
    processing_configuration {
      enabled = true

      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.lambda_purchase_details_firehose_transformation.arn}:$LATEST"
        }
      }

      processors {
        type = "AppendDelimiterToRecord"
      }
    }

    data_format_conversion_configuration {
      input_format_configuration {
        deserializer {
          hive_json_ser_de {

          }
        }
      }

      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression = var.parquet_compression_format
          }
        }
      }

      schema_configuration {
        database_name = aws_glue_catalog_database.catalog_database.name
        role_arn      = aws_iam_role.kinesis_firehose_purchase_details_role.arn
        table_name    = aws_glue_catalog_table.aws_glue_purchase_details_table.name
      }
    }
  }
}

#GLUE TABLE PURCHASE DETAILS RESOURCE
#################################################################################################################

resource "aws_glue_catalog_table" "aws_glue_purchase_details_table" {
  name          = "purchase-details-${var.app_name}-${var.app_environment}-table"
  database_name = aws_glue_catalog_database.catalog_database.name

  table_type = "EXTERNAL_TABLE"

  parameters = {
    EXTERNAL              = "TRUE"
    "parquet.compression" = "${var.parquet_compression_format}"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.bucket_data_storage.id}/purchase_details/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"

      parameters = {
        "serialization.format" = 1
      }
    }

    columns {
      name = "order_id"
      type = "string"
    }

    columns {
      name = "payment_type"
      type = "string"
    }

    columns {
      name = "amount"
      type = "double"
    }

    columns {
      name = "currency"
      type = "string"
    }

    columns {
      name = "instalments"
      type = "int"
    }

  }

}