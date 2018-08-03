#!/bin/bash

source_region="us-west-2"
target_region="us-east-2"
target_account_id="xxx"
source_profile="xxx"
target_profile="xxx"
source_account_source_region_stack_name="xxx"
source_account_source_region_snapshot_retention_number=2
source_account_target_region_stack_name="xxx"
source_account_target_region_snapshot_retention_number=2
dr_account_target_region_stack_name="xxx"
dr_account_target_region_snapshot_retention_number=4
snapshot_frequency='rate(5 minutes)'

aws cloudformation deploy \
    --template-file ./rds_dr_source_acct_source_region.yaml \
    --stack-name $source_account_source_region_stack_name \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides SourceRegion=$source_region DRRegion=$target_region SnapshotFrequency="${snapshot_frequency}" MaxSnapshotRetention=$source_account_source_region_snapshot_retention_number \
    --region $source_region \
    --profile $source_profile

aws cloudformation deploy \
    --template-file ./rds_dr_source_acct_target_region.yaml \
    --stack-name $source_account_target_region_stack_name \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides DRAccountId=$target_account_id DRRegion=$target_region MaxSnapshotRetention=$source_account_target_region_snapshot_retention_number \
    --region $target_region \
    --profile $source_profile

aws cloudformation deploy \
    --template-file ./rds_dr_dr_acct_target_region.yaml \
    --stack-name $dr_account_target_region_stack_name \
    --capabilities CAPABILITY_IAM \
    --parameter-overrides DRRegion=$target_region MaxSnapshotRetention=$dr_account_target_region_snapshot_retention_number \
    --region $target_region \
    --profile $target_profile

shared_sns_topic_arn=$(aws cloudformation describe-stacks \
    --stack-name $source_account_target_region_stack_name \
    --region $target_region \
    --profile $source_profile | jq -r '.Stacks[0].Outputs[0].OutputValue')

lambda_arn=$(aws cloudformation describe-stacks \
    --stack-name $dr_account_target_region_stack_name \
    --region $target_region \
    --profile $target_profile | jq -r '.Stacks[0].Outputs[0].OutputValue')

lambda_name=${lambda_arn##*:}

aws sns add-permission \
    --region $target_region \
    --topic-arn $shared_sns_topic_arn \
    --label lambda-access \
    --aws-account-id $target_account_id \
    --action-name Subscribe ListSubscriptionsByTopic Receive \
    --profile $source_profile

aws lambda add-permission \
    --function-name $lambda_name \
    --statement-id rds-copy-dr-snapshot \
    --action "lambda:InvokeFunction" \
    --principal sns.amazonaws.com \
    --source-arn $shared_sns_topic_arn \
    --profile $target_profile \
    --region $target_region

aws sns subscribe \
    --topic-arn $shared_sns_topic_arn \
    --protocol lambda \
    --notification-endpoint $lambda_arn \
    --profile $target_profile \
    --region $target_region