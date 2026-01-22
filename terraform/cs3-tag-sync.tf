# ============================================================================
# Lambda Function to Sync WorkSpaces Tags to SSM Managed Instances
# ============================================================================

# 1. The Python Script (Embedded)
resource "local_file" "tag_sync_script" {
  filename = "${path.module}/sync_tags.py"
  content  = <<-EOF
import boto3
import os

def lambda_handler(event, context):
    region = os.environ.get('AWS_REGION')
    ws_client = boto3.client('workspaces', region_name=region)
    ssm_client = boto3.client('ssm', region_name=region)

    print("🔄 Starting Tag Sync...")

    # 1. Get all WorkSpaces and build a map: ComputerName -> Role
    workspaces = ws_client.describe_workspaces()['Workspaces']
    computer_map = {}

    for ws in workspaces:
        c_name = ws.get('ComputerName')
        ws_id = ws.get('WorkspaceId')
        if c_name:
            # Get tags for this WorkSpace
            tags = ws_client.describe_tags(ResourceId=ws_id)['TagList']
            role_tag = next((t['Value'] for t in tags if t['Key'] == 'Role'), None)
            if role_tag:
                computer_map[c_name] = role_tag

    print(f"🔎 Found {len(computer_map)} WorkSpaces with 'Role' tags.")

    # 2. Get all SSM Instances
    # Note: In production, handle pagination (NextToken) for >50 instances
    ssm_instances = ssm_client.describe_instance_information(MaxResults=50)['InstanceInformationList']

    for instance in ssm_instances:
        inst_id = instance['InstanceId']
        c_name = instance.get('ComputerName')

        # Check if this instance belongs to a WorkSpace we know
        if c_name in computer_map:
            target_role = computer_map[c_name]
            
            # Check if it needs tagging (Optimization: Check existing tags first?)
            # For simplicity, we just apply the tag. It's idempotent.
            print(f"🏷️ Syncing {c_name} ({inst_id}) -> Role: {target_role}")
            
            ssm_client.add_tags_to_resource(
                ResourceType='ManagedInstance',
                ResourceId=inst_id,
                Tags=[{'Key': 'Role', 'Value': target_role}]
            )
            
            # Optional: Trigger Association immediately if needed, 
            # but SSM Schedule picks it up anyway.

    return {"status": "success", "synced_count": len(computer_map)}
EOF
}

# 2. Zip the Code
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = local_file.tag_sync_script.filename
  output_path = "${path.module}/sync_tags.zip"
}

# 3. IAM Role for Lambda
resource "aws_iam_role" "lambda_role" {
  name = "cs3_tag_sync_lambda_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "cs3_tag_sync_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "workspaces:DescribeWorkspaces",
          "workspaces:DescribeTags",
          "ssm:DescribeInstanceInformation",
          "ssm:AddTagsToResource",
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

# 4. The Lambda Function
resource "aws_lambda_function" "tag_sync" {
  filename         = data.archive_file.lambda_zip.output_path
  function_name    = "cs3-workspace-tag-sync"
  role             = aws_iam_role.lambda_role.arn
  handler          = "sync_tags.lambda_handler"
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256
  runtime          = "python3.9"
  timeout          = 60

  environment {
    variables = {
      PROJECT_ENV = var.environment
    }
  }
}

# 5. Schedule (EventBridge) - Run every 10 minutes
resource "aws_cloudwatch_event_rule" "schedule" {
  name                = "cs3-tag-sync-schedule"
  description         = "Sync WorkSpace tags to SSM every 5 minutes"
  schedule_expression = "rate(5 minutes)"
}

resource "aws_cloudwatch_event_target" "target" {
  rule      = aws_cloudwatch_event_rule.schedule.name
  target_id = "SyncTagsLambda"
  arn       = aws_lambda_function.tag_sync.arn
}

resource "aws_lambda_permission" "allow_cloudwatch" {
  statement_id  = "AllowExecutionFromCloudWatch"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.tag_sync.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.schedule.arn
}