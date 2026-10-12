resource "aws_dlm_lifecycle_policy" "snapshots" {
  description        = "${var.name} daily root-volume snapshots"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags = {
      Snapshot = var.name
    }

    schedule {
      name      = "daily"
      copy_tags = true

      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["08:00"] # UTC — 3–4am New York
      }

      retain_rule {
        count = var.snapshot_retain_count
      }
    }
  }
}
