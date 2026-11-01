output "instance_id" { value = aws_instance.web.id }
output "bucket_name" { value = aws_s3_bucket.data.bucket }
output "iam_users" { value = [aws_iam_user.intern.name, aws_iam_user.ci.name] }