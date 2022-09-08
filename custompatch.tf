terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.29.0"
    }
  }
}
provider "aws" {
  # profile = "default"
  region  = "us-east-1"
}

data "aws_caller_identity" "current" {}

data "aws_iam_role" "ssmpatchrole" {
  name = "AWSCloud-BHCStateManagerRole-us-east-1"
}

data "aws_ssm_patch_baseline" "BHCAWSLinux2Baseline" {
  name_prefix      = "BHC"
  owner            = "Self"
  operating_system = "AMAZON_LINUX_2"
}

resource "aws_ssm_maintenance_window" "testmaint" {
  name     = "lcctestmain"
  schedule = "rate(30 minutes)"
  duration = 3
  cutoff   = 1
  schedule_timezone = "America/Chicago"
  allow_unassociated_targets = "false"
}

resource "aws_ssm_maintenance_window_target" "target1" {
  window_id     = aws_ssm_maintenance_window.testmaint.id
  name          = "maintenance-window-target"
  description   = "This is a maintenance window target"
  resource_type = "INSTANCE"
  targets {
    key    = "tag:PatchGroup"
    values = ["testtfpatchgroup"]
  }
}

resource "aws_ssm_maintenance_window_task" "patch" {
  window_id        = aws_ssm_maintenance_window.testmaint.id
  name             = "testtfpatch"
  description      = "Apply patch management"
  task_type        = "RUN_COMMAND"
  task_arn         = "AWS-RunPatchBaseline"
  priority         = 1
  max_concurrency  = "10"
  max_errors       = "1"

  targets {
    key    = "WindowTargetIds"
    values = aws_ssm_maintenance_window_target.target1.*.id
  }

  task_invocation_parameters {
    run_command_parameters {
      timeout_seconds      = 600
      service_role_arn     = data.aws_iam_role.ssmpatchrole.arn
      parameter {
        name   = "Operation"
        values = ["Install"]
      }
      notification_config {
        notification_arn    = "arn:aws:sns:us-east-1:${data.aws_caller_identity.current.account_id}:BHC-PatchNotificationTopic"
        notification_events = ["All"]
        notification_type   = "Invocation"
      }
      parameter {
        name   = "RebootOption"
        values = ["RebootIfNeeded"]
      }
    }
  }
}

resource "aws_ssm_patch_group" "testtfpatchgroup" {
  baseline_id = data.aws_ssm_patch_baseline.BHCAWSLinux2Baseline.id
  patch_group = "testtfpatchgroup"
}
