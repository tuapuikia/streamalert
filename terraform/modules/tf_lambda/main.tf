// Generic module for any StreamAlert Lambda function.
// TODO - migrate all Lambda functions and Lambda metric alarms to use this module

locals {
  schedule_enabled = "${var.schedule_expression != ""}"
  vpc_enabled      = "${length(var.vpc_subnet_ids) > 0}"
}

// Either the function_vpc or the function_no_vpc resource will be used
resource "aws_lambda_function" "function_vpc" {
  count         = "${var.enabled && local.vpc_enabled ? 1 : 0}"
  function_name = "${var.function_name}"
  description   = "${var.description}"
  runtime       = "${var.runtime}"
  role          = "${aws_iam_role.role.arn}"
  handler       = "${var.handler}"
  memory_size   = "${var.memory_size_mb}"
  publish       = "${var.auto_publish_versions}"
  timeout       = "${var.timeout_sec}"
  s3_bucket     = "${var.source_bucket}"
  s3_key        = "${var.source_object_key}"

  // Maximum number of concurrent executions allowed
  reserved_concurrent_executions = "${var.concurrency_limit}"

  environment {
    variables = "${var.environment_variables}"
  }

  // Empty vpc_config lists are theoretically supported, but it actually breaks subsequent deploys:
  // https://github.com/terraform-providers/terraform-provider-aws/issues/443
  vpc_config {
    security_group_ids = "${var.vpc_security_group_ids}"
    subnet_ids         = "${var.vpc_subnet_ids}"
  }

  tags {
    Name = "${var.name_tag}"
  }

  // We need VPC access before the function can be created
  depends_on = ["aws_iam_role_policy_attachment.vpc_access"]
}

resource "aws_lambda_alias" "alias_vpc" {
  count            = "${var.enabled && local.vpc_enabled ? 1 : 0}"
  name             = "${var.alias_name}"
  description      = "${var.alias_name} alias for ${var.function_name}"
  function_name    = "${var.function_name}"
  function_version = "${var.aliased_version == "" ? aws_lambda_function.function_vpc.version : var.aliased_version}"
  depends_on       = ["aws_lambda_function.function_vpc"]
}

resource "aws_lambda_function" "function_no_vpc" {
  count         = "${var.enabled && !(local.vpc_enabled) ? 1 : 0}"
  function_name = "${var.function_name}"
  description   = "${var.description}"
  runtime       = "${var.runtime}"
  role          = "${aws_iam_role.role.arn}"
  handler       = "${var.handler}"
  memory_size   = "${var.memory_size_mb}"
  publish       = "${var.auto_publish_versions}"
  timeout       = "${var.timeout_sec}"
  s3_bucket     = "${var.source_bucket}"
  s3_key        = "${var.source_object_key}"

  // Maximum number of concurrent executions allowed
  reserved_concurrent_executions = "${var.concurrency_limit}"

  environment {
    variables = "${var.environment_variables}"
  }

  tags {
    Name = "${var.name_tag}"
  }
}

resource "aws_lambda_alias" "alias_no_vpc" {
  count            = "${var.enabled && !(local.vpc_enabled) ? 1 : 0}"
  name             = "${var.alias_name}"
  description      = "${var.alias_name} alias for ${var.function_name}"
  function_name    = "${var.function_name}"
  function_version = "${var.aliased_version == "" ? aws_lambda_function.function_no_vpc.version : var.aliased_version}"
  depends_on       = ["aws_lambda_function.function_no_vpc"]
}

// Allow Lambda function to be invoked via a CloudWatch event rule (if applicable)
resource "aws_lambda_permission" "allow_cloudwatch_invocation" {
  count         = "${var.enabled && local.schedule_enabled ? 1 : 0}"
  statement_id  = "AllowExecutionFromCloudWatch_${var.function_name}"
  action        = "lambda:InvokeFunction"
  function_name = "${var.function_name}"
  principal     = "events.amazonaws.com"
  source_arn    = "${aws_cloudwatch_event_rule.invocation_schedule.arn}"
  qualifier     = "${var.alias_name}"

  // The alias must be created before we can grant permission to invoke it
  depends_on = ["aws_lambda_alias.alias_vpc", "aws_lambda_alias.alias_no_vpc"]
}
