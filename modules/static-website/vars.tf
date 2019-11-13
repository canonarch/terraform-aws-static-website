variable "website_domain_name" {
}

variable "alias_domain_names" {
  type = list(string)
}

variable "acm_certificate_arn" {
}

variable "hosted_zone_id" {
}

variable "index_document" {
  default = "index.html"
}

variable "error_document" {
  default = "error.html"
}

variable "error_404_response_code" {
  default = 404
}

variable "error_document_404" {
  default = "error.html"
}

variable "cloudfront_price_class" {
  default = "PriceClass_All"
}

variable "min_ttl" {
  default = "0"
}

variable "default_ttl" {
  default = "86400"
}

variable "max_ttl" {
  default = "31536000"
}

variable "viewer_protocol_policy" {
  default = "redirect-to-https"
}

variable "force_destroy_website_bucket" {
  default = false
}

variable "force_destroy_access_logs_buckets" {
  default = false
}
