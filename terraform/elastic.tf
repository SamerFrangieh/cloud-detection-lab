# A queue: AWS drops a message here every time a new CloudTrail file lands
resource "aws_sqs_queue" "cloudtrail" {
  name                       = "${var.name}-cloudtrail-queue"
  visibility_timeout_seconds = 300
  message_retention_seconds  = 86400
}

# Let S3 post messages into the queue, but only from our logs bucket
resource "aws_sqs_queue_policy" "cloudtrail" {
  queue_url = aws_sqs_queue.cloudtrail.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "s3.amazonaws.com" }
      Action    = "sqs:SendMessage"
      Resource  = aws_sqs_queue.cloudtrail.arn
      Condition = { ArnEquals = { "aws:SourceArn" = aws_s3_bucket.logs.arn } }
    }]
  })
}

# Tell the logs bucket to notify the queue when a CloudTrail file arrives
resource "aws_s3_bucket_notification" "logs" {
  bucket      = aws_s3_bucket.logs.id
  eventbridge = true
  queue {
    queue_arn     = aws_sqs_queue.cloudtrail.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "cloudtrail/AWSLogs/${data.aws_caller_identity.me.account_id}/CloudTrail/"
    filter_suffix = ".json.gz"
  }
  depends_on = [aws_sqs_queue_policy.cloudtrail]
}

# Elastic's own user: can read the logs and the queue, nothing else
resource "aws_iam_user" "elastic_reader" {
  name          = "${var.name}-elastic-reader"
  force_destroy = true
}

resource "aws_iam_user_policy" "elastic_reader" {
  name = "read-logs-only"
  user = aws_iam_user.elastic_reader.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket"]
        Resource = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:ChangeMessageVisibility", "sqs:GetQueueUrl", "sqs:GetQueueAttributes"]
        Resource = aws_sqs_queue.cloudtrail.arn
      }
    ]
  })
}
