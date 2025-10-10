import boto3
import os

def lambda_handler(event, context):
    ec2 = boto3.client('ec2')
    sns = boto3.client('sns')

    instance_id = os.environ['INSTANCE_ID']
    sns_topic = os.environ['SNS_TOPIC_ARN']

    response = ec2.describe_instances(InstanceIds=[instance_id])
    state = response['Reservations'][0]['Instances'][0]['State']['Name']

    if state == 'running':
        sns.publish(
            TopicArn=sns_topic,
            Subject=f'Instance {instance_id} Still Running',
            Message=f'Instance {instance_id} has been running. Current state: {state}'
        )

    return {'statusCode': 200, 'body': f'Instance state: {state}'}
