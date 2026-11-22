data "archive_file" "disable_key" {
  type        = "zip"
  source_file = "${path.module}/../lambda/disable_key.py"
  output_path = "${path.module}/build/disable_key.zip"
}

resource "aws_iam_role" "responder" {
  name = "${var.name}-key-responder"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "responder" {
  name = "disable-keys-read-logs"
  role = aws_iam_role.responder.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["iam:UpdateAccessKey"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject"]
        Resource = "${aws_s3_bucket.logs.arn}/cloudtrail/*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "disable_key" {
  provider         = aws.notags
  function_name    = "${var.name}-disable-key"
  role             = aws_iam_role.responder.arn
  runtime          = "python3.12"
  handler          = "disable_key.handler"
  filename         = data.archive_file.disable_key.output_path
  source_code_hash = data.archive_file.disable_key.output_base64sha256
  timeout          = 30

  environment {
    variables = {
      SLACK_WEBHOOK_URL = var.slack_webhook_url
      ALLOWLIST         = "sam-admin,${var.name}-elastic-reader"
    }
  }
}

resource "aws_cloudwatch_event_rule" "new_cloudtrail_file" {
  provider    = aws.notags
  name        = "${var.name}-new-cloudtrail-file"
  description = "Fires when a new CloudTrail log file lands in the logs vault"
  event_pattern = jsonencode({
    source        = ["aws.s3"]
    "detail-type" = ["Object Created"]
    detail = {
      bucket = { name = [aws_s3_bucket.logs.bucket] }
      object = { key = [{ prefix = "cloudtrail/AWSLogs/${data.aws_caller_identity.me.account_id}/CloudTrail/" }] }
    }
  })
}

resource "aws_cloudwatch_event_target" "to_lambda" {
  provider = aws.notags
  rule     = aws_cloudwatch_event_rule.new_cloudtrail_file.name
  arn      = aws_lambda_function.disable_key.arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  provider      = aws.notags
  statement_id  = "AllowEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.disable_key.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.new_cloudtrail_file.arn
}