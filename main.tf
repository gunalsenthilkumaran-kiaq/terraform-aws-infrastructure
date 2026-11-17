
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "terraform-custom-vpc"
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-southeast-2a"
  map_public_ip_on_launch = true

  tags = {
    Name        = "terraform-public-subnet"
    Environment = "Development"
  }
}


resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "ap-southeast-2b"

  tags = {
    Name        = "terraform-private-subnet"
    Environment = "Development"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "terraform-public-route-table"
  }
}


resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "terraform-private-route-table"
  }
}


resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}


resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}





resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "terraform-internet-gateway"
  }
}


resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}






data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


data "aws_security_group" "default" {
  name   = "default"
  vpc_id = aws_vpc.main.id
}


resource "aws_instance" "public" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [data.aws_security_group.default.id]
  associate_public_ip_address = true

  credit_specification {
    cpu_credits = "standard"
  }


  tags = {
    Name        = "terraform-public-ec2"
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}






resource "aws_s3_bucket" "website" {
  bucket = "gunal-terraform-static-site-2026-unique123"

  tags = {
    Name        = "terraform-static-website"
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}


resource "aws_s3_bucket_versioning" "website" {
  bucket = aws_s3_bucket.website.id

  versioning_configuration {
    status = "Enabled"
  }
}


resource "aws_s3_bucket_server_side_encryption_configuration" "website" {
  bucket = aws_s3_bucket.website.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}


resource "aws_s3_bucket_public_access_block" "website" {
  bucket = aws_s3_bucket.website.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}






data "aws_s3_bucket" "static_site" {
  bucket = "gunal-terraform-static-site-2026-unique123"
}


resource "aws_cloudfront_origin_access_control" "static_site" {
  name                              = "gunal-static-site-oac"
  description                       = "OAC for Terraform static website"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}


resource "aws_cloudfront_distribution" "static_site" {
  enabled             = true
  comment             = "Gunal Terraform Static Website"
  default_root_object = "index.html"

  origin {
    domain_name              = data.aws_s3_bucket.static_site.bucket_regional_domain_name
    origin_id                = "S3-static-site-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.static_site.id
  }

  default_cache_behavior {
    target_origin_id       = "S3-static-site-origin"
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]

    compress = true

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = {
    Name        = "gunal-static-site-cdn"
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}


resource "aws_s3_bucket_policy" "cloudfront_access" {
  bucket = data.aws_s3_bucket.static_site.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "AllowCloudFrontServicePrincipal"
        Effect = "Allow"

        Principal = {
          Service = "cloudfront.amazonaws.com"
        }

        Action   = "s3:GetObject"
        Resource = "${data.aws_s3_bucket.static_site.arn}/*"

        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.static_site.arn
          }
        }
      }
    ]
  })
}


output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name"
  value       = aws_cloudfront_distribution.static_site.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID"
  value       = aws_cloudfront_distribution.static_site.id
}
