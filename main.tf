data "aws_region" "current" {}

provider "aws" {
  region = "us-east-1"
  alias  = "us-east-1"
}

module "lambda_at_edge" {
  source = "terraform-aws-modules/lambda/aws"

  lambda_at_edge = true

  function_name = "cognito-at-edge"
  description   = "Cognito authentication made easy to protect your website with CloudFront and Lambda@Edge."
  handler       = "src/index.handler"
  runtime       = "nodejs14.x"

  providers = {
    aws = aws.us-east-1
  }

  source_path = [
    {
      path = path.module,
      commands = [
        "npm install",
        ":zip"
      ],
      patterns = [
        "!.*",
        "src/.+",
        "node_modules/.+"
      ]
    }
  ]
}

module "s3_bucket" {
  source = "terraform-aws-modules/s3-bucket/aws"

  bucket = var.bucket_name
  acl    = "private"

  versioning = {
    enabled = true
  }

  block_public_acls       = true
  block_public_policy     = true
  restrict_public_buckets = true

  attach_policy = true
  policy        = data.aws_iam_policy_document.s3_bucket_policy.json
}

data "aws_iam_policy_document" "s3_bucket_policy" {
  statement {
    actions = [
      "s3:GetObject",
    ]

    resources = [
      "arn:aws:s3:::${var.bucket_name}/*",
    ]

    principals {
      type        = "AWS"
      identifiers = module.cdn.cloudfront_origin_access_identity_iam_arns
    }
  }

  statement {
    actions = [
      "s3:ListBucket",
    ]

    resources = [
      "arn:aws:s3:::${var.bucket_name}",
    ]

    principals {
      type        = "AWS"
      identifiers = module.cdn.cloudfront_origin_access_identity_iam_arns
    }
  }
}

module "log_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 2.0"

  bucket = "logs-static-hosting-cdn"
  acl    = null
  force_destroy = true
}

module "cdn" {
  source = "terraform-aws-modules/cloudfront/aws"

  enabled     = true
  price_class = "PriceClass_All"

  create_origin_access_identity = true
  origin_access_identities = {
    s3_bucket = "CloudFront can access S3 bucket"
  }

  logging_config = {
    bucket = module.log_bucket.s3_bucket_bucket_domain_name
    prefix = "cloudfront"
  }

  origin = {
    s3_bucket = {
      domain_name = module.s3_bucket.s3_bucket_bucket_regional_domain_name
      s3_origin_config = {
        origin_access_identity = "s3_bucket" # key in `origin_access_identities`
      }
      custom_header = [
        {
          name  = "x-user-pool-region"
          value = data.aws_region.current.name
        },
        {
          name  = "x-user-pool-id"
          value = aws_cognito_user_pool.default.id
        },
        {
          name  = "x-user-pool-app-client-id"
          value = aws_cognito_user_pool_client.default.id
        },
        {
          name  = "x-user-pool-domain"
          value = "${aws_cognito_user_pool_domain.main.domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
        }
      ]
    }
  }

  // Enable when aliases are needed
  // aliases = []

  // Check if this is needed
  // default_root_object = index.html

  default_cache_behavior = {
    target_origin_id       = "s3_bucket"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD", "OPTIONS"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true
    query_string    = true

    lambda_function_association = {
      viewer-request = {
        lambda_arn = module.lambda_at_edge.lambda_function_qualified_arn
      }
    }
  }
}

resource "aws_cognito_user_pool" "default" {
  name                     = "static-hosting-user-pool"
  auto_verified_attributes = ["email"]
}

resource "aws_cognito_user_pool_domain" "main" {
  domain       = "static-hosting-user-pool"
  user_pool_id = aws_cognito_user_pool.default.id
}

resource "aws_cognito_user_pool_client" "default" {
  name = "static-hosting-user-pool-client"

  user_pool_id                 = aws_cognito_user_pool.default.id
  supported_identity_providers = ["COGNITO", "Google"]
}

resource "aws_cognito_identity_provider" "google" {
  user_pool_id  = aws_cognito_user_pool.default.id
  provider_name = "Google"
  provider_type = "Google"

  provider_details = {
    authorize_scopes              = "profile email openid"
    client_id                     = var.google_oauth_client_id
    client_secret                 = var.google_oauth_client_secret
    token_url                     = "https://www.googleapis.com/oauth2/v4/token"
    token_request_method          = "POST"
    oidc_issuer                   = "https://accounts.google.com"
    authorize_url                 = "https://accounts.google.com/o/oauth2/v2/auth"
    attributes_url                = "https://people.googleapis.com/v1/people/me?personFields="
    attributes_url_add_attributes = "true"
  }

  attribute_mapping = {
    email    = "email"
    username = "sub"
  }
}
