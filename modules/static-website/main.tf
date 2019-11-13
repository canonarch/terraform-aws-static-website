terraform {
  required_version = ">= 0.12"
}

resource "aws_s3_bucket" "website" {
  bucket = local.website_bucket_name
  acl    = "private"
  policy = data.aws_iam_policy_document.bucket_policy.json

  website {
    index_document = var.index_document
    error_document = var.error_document
  }

  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "AES256"
      }
    }
  }

  logging {
    target_bucket = aws_s3_bucket.s3_access_logs.id
  }

  force_destroy = "${var.force_destroy_website_bucket}"
}

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["arn:aws:s3:::${local.website_bucket_name}/*"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
    }
  }

  statement {
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${local.website_bucket_name}"]

    principals {
      type        = "AWS"
      identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
    }
  }
}

resource "aws_cloudfront_distribution" "website" {
  depends_on = [aws_s3_bucket.website]

  aliases = var.alias_domain_names
  enabled = "true"

  is_ipv6_enabled = "true"
  price_class     = var.cloudfront_price_class

  origin {
    domain_name = "${local.website_bucket_name}.s3.amazonaws.com"
    origin_id   = local.website_bucket_name
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  default_root_object = var.index_document

  custom_error_response {
    error_code         = 404
    response_code      = var.error_404_response_code
    response_page_path = "/${var.error_document_404}"
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    minimum_protocol_version = "TLSv1.2_2018"
    ssl_support_method       = "sni-only"
  }

  default_cache_behavior {
    allowed_methods = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods  = ["GET", "HEAD"]
    compress        = "true"

    min_ttl     = var.min_ttl
    default_ttl = var.default_ttl
    max_ttl     = var.max_ttl

    target_origin_id       = local.website_bucket_name
    viewer_protocol_policy = var.viewer_protocol_policy

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    lambda_function_association {
      event_type = "origin-response"
      lambda_arn = module.apply_security_headers_lambda_edge.function_qualified_arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  logging_config {
    bucket = "${aws_s3_bucket.cloudfront_access_logs.id}.s3.amazonaws.com"
  }
}

resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {
  comment = "access-identity-${local.website_bucket_name}"
}

resource "aws_route53_record" "record_a" {
  count = length(var.alias_domain_names)

  zone_id = var.hosted_zone_id
  name    = element(var.alias_domain_names, count.index)
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "record_aaaa" {
  count = length(var.alias_domain_names)

  zone_id = var.hosted_zone_id
  name    = element(var.alias_domain_names, count.index)
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.website.domain_name
    zone_id                = aws_cloudfront_distribution.website.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_s3_bucket" "s3_access_logs" {
  bucket = "${local.website_bucket_name}-logs"
  acl    = "log-delivery-write"

  lifecycle_rule {
    id      = "log"
    enabled = true

    expiration {
      days = 90
    }
  }

  force_destroy = "${var.force_destroy_access_logs_buckets}"
}

resource "aws_s3_bucket" "cloudfront_access_logs" {
  bucket = "${local.website_bucket_name}-cloudfront-logs"
  acl    = "log-delivery-write"

  lifecycle_rule {
    id      = "log"
    enabled = true

    expiration {
      days = 90
    }
  }

  force_destroy = "${var.force_destroy_access_logs_buckets}"
}

# Apply security headers to the Cloudfront distribution with a Lambda@Edge
# cf https://aws.amazon.com/blogs/networking-and-content-delivery/adding-http-security-headers-using-lambdaedge-and-amazon-cloudfront/
module "apply_security_headers_lambda_edge" {
  source = "git@github.com:canonarch/terraform-aws-lambda.git//modules/lambda-edge?ref=v0.0.1"
  function_name = substr(
    replace(
      "applySecurityHeadersToCloudfront_${var.website_domain_name}",
      ".",
      "_",
    ),
    0,
    64,
  )
  description = "Apply HTTP security headers to Cloudfront ${var.website_domain_name}"
  source_dir  = "${path.module}/apply_security_headers_lambda_edge"
  handler     = "index.handler"
  runtime     = "nodejs8.10"
  memory_size = 128
}

# ---------------------------------------------------------------------------------------------------------------------
# LOCALS VARIABLES
# ---------------------------------------------------------------------------------------------------------------------

locals {
  website_bucket_name = var.website_domain_name
}

