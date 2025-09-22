variable "s3" {
  description = "AWS s3 bucket for managing the state file"
  type = object({
    key = string,
    region = string
  })
}

variable "bucket_name" {
  description = "Globally unique name for AWS bucket"
  type        = string
}

