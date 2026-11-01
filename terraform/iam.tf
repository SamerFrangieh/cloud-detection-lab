resource "aws_iam_user" "intern" {
  name = "${var.name}-dev-intern"
}

resource "aws_iam_user_policy" "intern_too_broad" {
  name = "intern-too-broad"
  user = aws_iam_user.intern.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["iam:*", "s3:*", "ec2:*"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_user" "ci" {
  name = "${var.name}-ci-deploy"
}

resource "aws_iam_user_policy_attachment" "ci_s3" {
  user       = aws_iam_user.ci.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}