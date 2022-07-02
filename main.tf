data "aws_region" "current" {}

module "lambda_at_edge" {
  source = "terraform-aws-modules/lambda/aws"

  lambda_at_edge = true

  function_name = "cognito-at-edge"
  description   = "Cognito authentication made easy to protect your website with CloudFront and Lambda@Edge."
  handler       = "src/index.handler"
  runtime       = "nodejs14.x"

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

  environment_variables = {
    USER_POOL_REGION        = data.aws_region.current.name
    USER_POOL_ID            = aws_cognito_user_pool.default.id
    USER_POOL_APP_CLIENT_ID = aws_cognito_user_pool_client.default.id
    USER_POOL_DOMAIN        = aws_cognito_user_pool.default.domain
  }
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

module "cdn" {
  source = "terraform-aws-modules/cloudfront/aws"

  enabled     = true
  price_class = "PriceClass_All"

  create_origin_access_identity = true
  origin_access_identities = {
    s3_bucket = "CloudFront can access S3 bucket"
  }

  origin = {
    s3_bucket = {
      domain_name = module.s3_bucket.s3_bucket_bucket_regional_domain_name
      s3_origin_config = {
        origin_access_identity = "s3_bucket_one" # key in `origin_access_identities`
      }
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
