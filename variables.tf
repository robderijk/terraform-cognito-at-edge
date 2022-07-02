variable "bucket_name" {
  type        = string
  description = "The name of your s3 bucket"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to label resources with (e.g map('dev', 'prod'))"
}

variable "google_oauth_client_id" {
  type        = string
  description = "Google OAuth client ID"
}
variable "google_oauth_client_secret" {
  type        = string
  description = "Google OAuth client secret"
}
