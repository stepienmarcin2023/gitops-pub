# Data Disks
data "aws_partition" "current" {}

locals {
  aws_partition = data.aws_partition.current.partition
  node_data_disks = flatten([
    for i in range(var.node_count) :
    [
      for data_disk in var.data_disks : {
        name                           = data_disk.name
        num                            = index(var.data_disks, data_disk)
        type                           = lookup(data_disk, "type", var.disk_type)
        size                           = lookup(data_disk, "size", var.disk_size)
        iops                           = lookup(data_disk, "iops", null)
        device_name                    = data_disk.device_name
        availability_zone              = aws_instance.gitlab[i].availability_zone
        instance_id                    = aws_instance.gitlab[i].id
        instance_name                  = aws_instance.gitlab[i].tags_all["Name"]
        instance_num                   = i
        instance_disk_num              = index(var.data_disks, data_disk)
        skip_destroy                   = lookup(data_disk, "skip_destroy", null)
        stop_instance_before_detaching = true
      }
      if data_disk.name != null
    ]
  ])
}

resource "aws_ebs_volume" "gitlab" {
  for_each = { for d in local.node_data_disks : "${d.instance_name}-${d.name}" => d }

  type              = each.value.type
  size              = each.value.size
  iops              = each.value.iops
  availability_zone = each.value.availability_zone

  encrypted  = true
  kms_key_id = var.disk_kms_key_arn

  tags = {
    Name                       = each.key
    gitlab_node_data_disk_role = "${var.prefix}-${var.node_type}-${each.value.name}"
  }
}

resource "aws_volume_attachment" "gitlab" {
  for_each = { for d in local.node_data_disks : "${d.instance_name}-${d.name}" => d }

  device_name                    = each.value.device_name
  volume_id                      = aws_ebs_volume.gitlab[each.key].id
  instance_id                    = each.value.instance_id
  skip_destroy                   = each.value.skip_destroy
  stop_instance_before_detaching = each.value.stop_instance_before_detaching
}

## Data Disk Snapshots (DLM)
locals {
  node_data_disks_snapshots = [
    for data_disk in var.data_disks : {
      name      = data_disk.name
      snapshots = data_disk.snapshots
    }
    if contains(keys(data_disk), "snapshots")
  ]
}

resource "aws_iam_role" "gitlab_dlm" {
  count = min(length(local.node_data_disks_snapshots), 1)

  name = "${var.prefix}-${var.node_type}-dlm-snapshot-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      },
    ]
  })

  path                 = var.iam_identifier_path
  permissions_boundary = var.iam_permissions_boundary_arn
}

resource "aws_iam_role_policy" "gitlab_dlm" {
  count = min(length(local.node_data_disks_snapshots), 1)

  name = "${var.prefix}-${var.node_type}-dlm-snapshot-policy"
  role = aws_iam_role.gitlab_dlm[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeVolumes",
          "ec2:DescribeSnapshots"
        ]
        Effect   = "Allow"
        Resource = "*"
      },
      {
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateSnapshots",
          "ec2:CreateTags"
        ]
        Effect    = "Allow"
        Resource  = "arn:${local.aws_partition}:ec2:*::snapshot/*"
        Condition = { "StringLike" = { "aws:RequestTag/gitlab_node_data_disk_role" = "${var.prefix}-${var.node_type}-*" } }
      },
      {
        Action = [
          "ec2:DeleteSnapshot"
        ]
        Effect    = "Allow"
        Resource  = "arn:${local.aws_partition}:ec2:*::snapshot/*"
        Condition = { "StringLike" = { "aws:ResourceTag/gitlab_node_data_disk_role" = "${var.prefix}-${var.node_type}-*" } }
      },
      {
        Action = [
          "ec2:CreateSnapshots",
        ]
        Effect    = "Allow"
        Resource  = "arn:${local.aws_partition}:ec2:*:*:instance/*"
        Condition = { "StringEquals" = { "aws:ResourceTag/gitlab_node_prefix" = var.prefix, "aws:ResourceTag/gitlab_node_type" = var.node_type } }
      },
      {
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateSnapshots"
        ]
        Effect    = "Allow"
        Resource  = "arn:${local.aws_partition}:ec2:*:*:volume/*"
        Condition = { "StringLike" = { "aws:ResourceTag/gitlab_node_data_disk_role" = "${var.prefix}-${var.node_type}-*" } }
      }
    ]
  })
}

resource "aws_dlm_lifecycle_policy" "gitlab_dlm" {
  for_each = { for ds in local.node_data_disks_snapshots : "${var.prefix}-${var.node_type}-${ds.name}" => ds }

  description        = "DLM policy for ${each.key} data disks"
  execution_role_arn = aws_iam_role.gitlab_dlm[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]

    schedule {
      name = "Schedule for ${each.key} data disks"

      create_rule {
        interval = each.value.snapshots.interval
        times    = [each.value.snapshots.start_time]
      }

      retain_rule {
        count = each.value.snapshots.retain_count
      }

      copy_tags = true
    }

    target_tags = {
      gitlab_node_data_disk_role = each.key
    }
  }

  tags = {
    Name = "${each.key}-snapshot-policy"
  }
}
