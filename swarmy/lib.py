import boto3
import requests
import time
import os
import sys
from functools import wraps

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

class EC2Metadata:
    """
    A class to handle AWS EC2 instance metadata and tags operations.

    This class provides methods to interact with EC2 instance metadata, manage tags,
    and perform Route53 DNS operations. It implements caching for metadata and tags
    to minimize API calls.

    Attributes:
        _metadata (dict): Cache for instance metadata
        _tags (dict): Cache for instance tags
        _region (str): Cache for AWS region
    """
    def __init__(self):
        self._metadata = None
        self._tags = None
        self._region = None

    def metadata_required(func):
        """
        A decorator that ensures instance metadata is loaded before function execution.

        Args:
            func: The function to be wrapped

        Returns:
            wrapper: The wrapped function that checks for metadata
        """
        @wraps(func)
        def wrapper(self, *args, **kwargs):
            if self._metadata is None:
                self._metadata = get_instance_metadata()
            return func(self, *args, **kwargs)
        return wrapper

    @metadata_required
    def get_region(self):
        if not self._region:
            self._region = self._metadata['region']
        return self._region

    @metadata_required
    def get_instance_tags(self):
        """
        Retrieve all tags associated with the current EC2 instance.

        This method caches the tags to minimize API calls to AWS.
        If tags are already cached, returns the cached version.

        Returns:
            dict: A dictionary of instance tags where keys are tag names
                 and values are tag values.

        Example:
            >>> ec2_meta = EC2Metadata()
            >>> tags = ec2_meta.get_instance_tags()
            >>> print(tags)
            {'Name': 'my-instance', 'Environment': 'production'}
        """
        if self._tags is None:
            instance_id = self._metadata['instanceId']
            ec2 = boto3.resource('ec2', region_name=self.get_region())
            instance = ec2.Instance(instance_id)
            self._tags = {tag['Key']: tag['Value'] for tag in instance.tags or []}
        return self._tags

    @metadata_required
    def set_instance_tag(self, key, value):
        """
        Set a tag on the current EC2 instance.

        Args:
            key (str): The tag key to set
            value (str): The value to set for the tag

        Returns:
            dict: Updated dictionary of all instance tags

        Raises:
            boto3.exceptions.Boto3Error: If the tag update fails

        Example:
            >>> ec2_meta = EC2Metadata()
            >>> ec2_meta.set_instance_tag('Environment', 'production')
        """
        instance_id = self._metadata['instanceId']
        ec2 = boto3.resource('ec2', region_name=self.get_region())
        instance = ec2.Instance(instance_id)
        instance.create_tags(Tags=[{'Key': key, 'Value': value}])
        self._tags = None  # Reset cache
        return self.get_instance_tags()

    def set_instance_name(self, fqdn):
        """Set the Name tag of the instance"""
        return self.set_instance_tag('Name', fqdn)

    @metadata_required
    def route53_upsert_a_record(self, domain, fqdn, ip, ttl, wait=0):
        """
        Update or create an A record in Route53 DNS.

        This method will either create a new A record or update an existing one
        in the specified Route53 hosted zone.

        Args:
            domain (str): The domain name of the hosted zone (e.g., 'example.com')
            fqdn (str): The fully qualified domain name for the A record
            ip (str): The IP address for the A record
            ttl (int): Time-to-live in seconds for the DNS record
            wait (int): Time in seconds to wait for the change to propagate.
                       Use -1 to wait indefinitely, 0 to return immediately.

        Returns:
            dict: The Route53 change response object

        Raises:
            ValueError: If the hosted zone for the domain is not found
            boto3.exceptions.Boto3Error: If the Route53 API call fails

        Example:
            >>> ec2_meta = EC2Metadata()
            >>> ec2_meta.route53_upsert_a_record(
            ...     domain='example.com',
            ...     fqdn='server1.example.com',
            ...     ip='10.0.0.1',
            ...     ttl=300,
            ...     wait=60
            ... )
        """
        route53 = boto3.client('route53', region_name=self.get_region())

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

    Args:
        fqdn (str): The fully qualified domain name to set as hostname

    Returns:
        int: Return code from the hostname command (0 for success)

    Example:
        >>> set_hostname('server1.example.com')
        0
    """
    return os.system(f"hostname {fqdn}")
