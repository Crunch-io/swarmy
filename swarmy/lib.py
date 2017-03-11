import boto, boto.utils, boto.ec2, boto.route53
import time
import os,sys

#import ipdb; st=ipdb.set_trace

from _version import version

get_instance_metadata = boto.utils.get_instance_metadata

_i_metadata = None
_i_tags = None

def error(errno, message):
    print >>sys.stderr, message
    return errno

def metadata_required(func):
    def metadata_acquirer_wrapper(*a, **kw):
        global _i_metadata
        if _i_metadata is None:
            _i_metadata = get_instance_metadata()

        return func(*a, **kw)
    return metadata_acquirer_wrapper

@metadata_required
def get_region():
    global _i_metadata, _i_tags
    return _i_metadata['placement']['availability-zone'][:-1]

@metadata_required
def get_instance_tags():
    global _i_metadata, _i_tags
    '''
    Returns the instance tags for the instance ID provided (region also
    required). If `None` is provided, the instance's own ID (with the region)
    will be retrieved from instance metadata, and used.

    Returns a dictionary of tag names to values:
    ```
    {
      u'Name': u'eu-zz9-01.priveu.crunch.io',
      u'Domain': u'priveu.crunch.io',
      u'aws:autoscaling:groupName': u'eu-zz9',
      u'costgroup': u'production'
    }
    ```
    '''
    instanceId = _i_metadata['instance-id']
    #assumes that the availability zone is a single character at the end of the region
    region = get_region()

    if _i_tags is None:
        # Get the list of tags for the instanceId
        ec2conn = boto.ec2.connect_to_region(region)
        res = ec2conn.get_all_instances(instance_ids=[instanceId])
        inst = res[0].instances[0]
        _i_tags = inst.tags
    return _i_tags

@metadata_required
def set_instance_tag(key, value):
    global _i_metadata, _i_tags
    '''
    Set's the instance tag for the current instance id/region retrieved from
    metadata.

    '''
    instanceId = _i_metadata['instance-id']
    #assumes that the availability zone is a single character at the end of the region
    region = get_region()

    ec2conn = boto.ec2.connect_to_region(region)
    res = ec2conn.get_all_instances(instance_ids=[instanceId])
    inst = res[0].instances[0]
    inst.add_tag(key, value)
    _i_tags = inst.tags
    return _i_tags

def set_instance_name(fqdn):
    return set_instance_tag('Name', fqdn)

def instance_tags_required(func):
    def tags_acquirer_wrapper(*a, **kw):
        global _i_tags
        if _i_tags is None:
            _i_tags = get_instance_tags()

        return func(*a, **kw)
    return tags_acquirer_wrapper

@metadata_required
def route53_upsert_a_record(domain, fqdn, ip, ttl, wait=0):
    """
    Update the record in route53.
    """
    global _i_metadata


    region = get_region()
    r53conn = boto.route53.connect_to_region(region)
    zone = r53conn.get_zone(domain)
    #TODO health check to remove this record automatically
    cs = boto.route53.record.ResourceRecordSets(r53conn,zone.id)
    c1 = cs.add_change('UPSERT', fqdn, type='A', ttl=ttl)
    c1.add_value(ip)

    s = cs.commit()
    # {u'ChangeResourceRecordSetsResponse': {u'ChangeInfo': {u'Status': u'PENDING', u'Comment': u'None', u'SubmittedAt': u'2016-11-02T21:31:39.648Z', u'Id': u'/change/C34YG36BA6E029'}}}

    if wait == -1:
        stoptime = sys.maxint
    else:
        stoptime = time.time() + wait

    while s.values()[0]['ChangeInfo']['Status'] == u'PENDING':
        if time.time() > stoptime:
            break
        time.sleep(10)
        s.update()

##Now set the hostname
def set_hostname(fqdn):
    os.system("hostname %s" % fqdn)

