"""
dynamic_hostname - A script that gathers the hostname and
domain from various pieces of available metadata, and then
sets the hostname, and registers the fqdn with Route53.

Uses instance metadata and instance tags, or specify on the
command line all the data you need.

Usage:
  dynamic_hostname [-0|-1|-2|-3] [options] (--domain-tag=<domain_tag>|--domain=<domain>)

Options:
  -h --help     Show this screen.
  -V --version  Show version.
  -q            Do not print the hostname to stdout
  -D --debug    Print some debugging
  -H --no-host  Do NOT set the hostname
  -D --no-dns   Do NOT set up the DNS
  -N --no-ec2-name
                Do NOT add the new hostname as the "Name" tag on the instance
  -S --screen-only
                Only print the hostname to the screen, implies --no-host and --no-dns
  -P --public   Use the public IP instead of the private (Private ip is used by default)
  -0            Don't use any parts of the IP address
  -1            Use the last part of the IP only
  -2            Use the last 2 parts
  -3            Use the last 3 parts
  --domain=<domain>
                If given, use directly instead of looking up the Domain from the instance tags
  --domain-tag=<domain_tag>
                Instance tag name to use to retrieve name. Overrides --domain
  --hosted-zone=<hosted_zone>
                By default, we try to add the hostname to the zone name found using --domain or --domain-tag, but if this is different for you, specify this parameter. Ignored if --no-dns is specified
  --prefix=<prefix>
                The hostname prefix to use. Will be used verbatim (no '-' will be appended). E.g., 'ip' will become 'ip10-2-3-4' and 'ip-' will become 'ip-10-2-3-4' [default: ip-]
  --prefix-tag=<prefix_tag>
                Instance tag to use as the prefix. Overrides --prefix
  --prefix-sep=<sep>
                Append <sep> to the prefix before appending the ip address parts, omit argument to leave blank
  --ttl=<ttl>   TTL to send to route53 for DNS record [default: 3600]
  --wait=<timeout>
                After updating route53, wait for the record to synchronize approximately <timeout> seconds before continuing. If the record returns as INSYNC, the script continues sooner [default: 0]
"""

import lib
from docopt import docopt

helpstr = __doc__

@lib.metadata_required
def get_ip(public=False):
    """
    Get the current ip address (private by default)
    """
    if public:
        return lib._i_metadata.get('public-ipv4', '169.254.0.1')
    else:
        return lib._i_metadata['local-ipv4']

@lib.instance_tags_required
def get_domain_from_tags(tagName):
    if tagName in lib._i_tags:
        return lib._i_tags[tagName]

@lib.instance_tags_required
def get_prefix_from_tags(tagName):
    if tagName in lib._i_tags:
        return lib._i_tags[tagName]

def gen_fqdn(ip, hostprefix, numparts=2, domain='example.com', sep=''):
    # split off the unique parts
    if numparts >= 1:
        host_ip_part = '-'.join(ip.split('.')[0-numparts:])
    else:
        host_ip_part = ""

    return hostprefix + sep + host_ip_part + '.' + domain

def main():
    """
    Do stuff.
    """
    arguments = docopt(helpstr, version="dynamic_hostname %s" % lib.version)

    #print arguments

    if arguments['-0']:
        numparts = 0
    elif arguments['-1']:
        numparts = 1
    elif arguments['-2']:
        numparts = 2
    elif arguments['-3']:
        numparts = 3
    else:
        numparts = 4

    #prefix has default value of 'ip-'
    prefix = arguments['--prefix']
    #prefix-tags overrides if present
    if arguments['--prefix-tag'] is not None:
        prefix = get_prefix_from_tags(arguments['--prefix-tag'])
        if not prefix:
            return lib.error(2, "No tag with that name (%s)" % arguments['--prefix-tag'])

    domain = None
    # --domain and --domain-tags are mut. ex.
    if arguments['--domain']:
        domain = arguments['--domain']
    if arguments['--domain-tag']:
        domain = get_domain_from_tags(arguments['--domain-tag'])
        if not domain:
            return lib.error(2, "No tag with that name, or tag empty (%s)" % arguments['--domain-tag'])

    #Final check
    if domain is None:
        return lib.error(2, "Can't figure out the domain to use")

    ip = get_ip(arguments['--public'])
    sep = arguments['--prefix-sep'] or ''

    fqdn = gen_fqdn(ip, prefix, numparts, domain, sep)

    if not arguments['--screen-only']:
        if not arguments['--no-dns']:
            hzone = domain
            if arguments['--hosted-zone']:
                hzone = arguments['--hosted-zone']
            ttl = int(arguments['--ttl'])
            wait = int(arguments['--wait'])
            lib.route53_upsert_a_record(hzone, fqdn, ip, ttl, wait)

        if not arguments['--no-host']:
            lib.set_hostname(fqdn)

        if not arguments['--no-ec2-name']:
            lib.set_instance_name(fqdn)

    if not arguments['-q']:
        print fqdn

    return 0

if __name__ == '__main__':
    import sys
    sys.exit(main() or 0)
    main()
