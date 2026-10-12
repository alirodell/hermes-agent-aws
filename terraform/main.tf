data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "${var.name}-data-${local.account_id}-${var.region}"
  secret_name = "${var.name}/hermes-env"
}
