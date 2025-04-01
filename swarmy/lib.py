import boto3
import requests
import time
import os
import sys
from functools import wraps

# Global cache for metadata and tags
_metadata_cache = None
_tags_cache = None
_region_cache = None

def error(errno, message):
    print(message, file=sys.stderr)
    return errno

def get_instance_metadata():
    """Get instance metadata using IMDSv2"""
    token_url = "http://169.254.169.254/latest/api/token"
    token_headers = {"X-aws-ec2-metadata-token-ttl-seconds": "3600"}
    token = requests.put(token_url, headers=token_headers).text

    metadata_url = "http://169.254.169.254/latest/dynamic/instance-identity/document"
    metadata_headers = {"X-aws-ec2-metadata-token": token}
    response = requests.get(metadata_url, headers=metadata_headers)
    return response.json()

def metadata_required(func):
    """
    A decorator that ensures instance metadata is loaded before function execution.
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        global _metadata_cache
        if _metadata_cache is None:
            _metadata_cache = get_instance_metadata()
        return func(*args, **kwargs)
    return wrapper

@metadata_required
def get_region():
    global _region_cache
    if not _region_cache:
        _region_cache = _metadata_cache['region']
    return _region_cache

@metadata_required
def get_instance_tags():
    """
    Retrieve all tags associated with the current EC2 instance.
    Returns a dictionary of instance tags.
    """
    global _tags_cache
    if _tags_cache is None:
        instance_id = _metadata_cache['instanceId']
        ec2 = boto3.resource('ec2', region_name=get_region())
        instance = ec2.Instance(instance_id)
        _tags_cache = {tag['Key']: tag['Value'] for tag in instance.tags or []}
    return _tags_cache

def instance_tags_required(func):
    """
    A decorator that ensures instance tags is loaded before function execution.
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        global _tags_cache
        if _metadata_cache is None:
            _metadata_cache = get_instance_tags()
        return func(*args, **kwargs)
    return wrapper

@metadata_required
def set_instance_tag(key, value):
    """
    Set a tag on the current EC2 instance.
    Returns updated dictionary of all instance tags.
    """
    global _tags_cache
    instance_id = _metadata_cache['instanceId']
    ec2 = boto3.resource('ec2', region_name=get_region())
    instance = ec2.Instance(instance_id)
    instance.create_tags(Tags=[{'Key': key, 'Value': value}])
    _tags_cache = None  # Reset cache
    return get_instance_tags()

def set_instance_name(fqdn):
    """Set the Name tag of the instance"""
    return set_instance_tag('Name', fqdn)

@metadata_required
def route53_upsert_a_record(domain, fqdn, ip, ttl, wait=0):
    """
    Update or create an A record in Route53 DNS.
    Returns the Route53 change response object.
    """
    route53 = boto3.client('route53', region_name=get_region())

    # Get the hosted zone ID
    zones = route53.list_hosted_zones_by_name(DNSName=domain)
    zone_id = None
    for zone in zones['HostedZones']:
        if zone['Name'].rstrip('.') == domain:
            zone_id = zone['Id']
            break

    if not zone_id:
        raise ValueError(f"Hosted zone for domain {domain} not found")

    # Prepare the change batch
    change_batch = {
        'Changes': [{
            'Action': 'UPSERT',
            'ResourceRecordSet': {
                'Name': fqdn,
                'Type': 'A',
                'TTL': ttl,
                'ResourceRecords': [{'Value': ip}]
            }
        }]
    }

    # Make the change
    response = route53.change_resource_record_sets(
        HostedZoneId=zone_id,
        ChangeBatch=change_batch
    )

    if wait:
        waiter = route53.get_waiter('resource_record_sets_changed')
        waiter.wait(
            Id=response['ChangeInfo']['Id'],
            WaiterConfig={'Delay': 10, 'MaxAttempts': 60 if wait == -1 else int(wait/10)}
        )

    return response

def set_hostname(fqdn):
    """
    Set the system hostname to the specified FQDN.
    Returns return code from the hostname command (0 for success).
    """
    return os.system(f"hostname {fqdn}")
