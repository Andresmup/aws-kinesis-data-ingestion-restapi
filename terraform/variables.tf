variable "app_name" {
  type        = string
  description = "Application Name"
  default     = "ingestion"
}

variable "app_environment" {
  type        = string
  description = "Application Environment"
  default     = "dev"
}

variable "stage_name" {
  type        = string
  description = "Stage name"
  default     = "apiv1"
}

variable "endpoint_name" {
  type        = string
  description = "Endpoint name"
  default     = "orders"
}


variable "lambda_handler" {
  type        = string
  description = "Lambda handler for python code <python_filename>.<function_name>"
  default     = "lambda_function.lambda_handler"
}

variable "python_runtime" {
  type        = string
  description = "Python lambda runtime"
  default     = "python3.12"
}

variable "github_org" {
  type        = string
  description = "Github organization"
  default     = "Andresmup"
}

variable "repository_name" {
  type        = string
  description = "Repository name"
  default     = "aws-kinesis-data-ingestion-restapi"
}

variable "account_id" {
  type        = string
  description = "Account id"
  default     = "604476232840"
}

variable "parquet_compression_format" {
  type        = string
  description = "Format used in parquet compression"
  default     = "SNAPPY"
}