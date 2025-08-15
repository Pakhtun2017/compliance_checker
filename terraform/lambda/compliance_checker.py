import json
import boto3
import os

sns_client = boto3.client("sns")
SNS_TOPIC_ARN = os.environ.get("SNS_TOPIC_ARN")


def check_compliance(file_content):
    try:
        data = json.loads(file_content)
        return data.get("compliant", False)
    except Exception:
        return False


def lambda_handler(event, context):
    bucket = event["Records"][0]["s3"]["bucket"]["name"]
    key = event["Records"][0]["s3"]["object"]["key"]

    s3_client = boto3.client("s3")
    response = s3_client.get_object(Bucket=bucket, Key=key)
    content = response["Body"].read().decode("utf-8")

    compliant = check_compliance(content)

    if not compliant:
        message = f"Compliance Check Failed for s3://{bucket}/{key}"
        print(message)
        sns_client.publish(
            TopicArn=SNS_TOPIC_ARN,
            Message=message,
            Subject="Compliance Violation Alert",
        )
    else:
        print(f"s3://{bucket}/{key} passed compliance check.")

    return {"statusCode": 200, "body": json.dumps({"compliant": compliant})}
