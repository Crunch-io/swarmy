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
                By default, we try to add the hostname to the zone name found using --domain or --domain-tag, but if this isdifferent for you, specify this parameter. Ignored if --no-dns is specified
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

from typing import Optional, Dict, Any, Union
from dataclasses import dataclass
from swarmy import lib, _version
from docopt import docopt
import sys

helpstr = __doc__

@dataclass
class HostnameConfig:
    """Configuration for hostname generation"""
    ip: str
    prefix: str
    numparts: int
    domain: str
    sep: str = ''

@lib.metadata_required
def get_ip(public: bool = False) -> Optional[str]:
    """
    Get the current ip address (private by default)

    Args:
        public: Whether to get public IP instead of private

    Returns:
        str: IP address
    """
    if public:
        return lib._metadata_cache['public-ipv4', '169.254.0.1']
    return lib._metadata_cache['privateIp']

@lib.instance_tags_required
def get_domain_from_tags(tagName: str) -> Optional[str]:
    """
    Get domain from instance tags

    Args:
        tagName: Name of the tag to look up

    Returns:
        Optional[str]: Domain name if found, None otherwise
    """
    return lib._tags_cache(tagName)

@lib.instance_tags_required
def get_prefix_from_tags(tagName: str) -> Optional[str]:
    """
    Get prefix from instance tags

    Args:
        tagName: Name of the tag to look up

    Returns:
        Optional[str]: Prefix if found, None otherwise
    """
    return lib._tags_cache(tagName)

def gen_fqdn(config: HostnameConfig) -> str:
    """
    Generate FQDN from configuration with proper IP part handling

    Args:
        config: HostnameConfig with ip, domain, numparts, prefix, and sep

    Returns:
        str: Generated FQDN

    Raises:
        ValueError: If IP is invalid or numparts is out of range
    """
    if config.numparts >= 1:
        host_ip_part = '-'.join(config.ip.split('.')[0-config.numparts:])
    else:
        host_ip_part = ""

    return f"{config.prefix}{host_ip_part}.{config.domain}"

def parse_arguments() -> Dict[str, Any]:
    """Parse and validate command line arguments"""
    return docopt(helpstr, version=f"dynamic_hostname {_version.version}")

def get_numparts(arguments: Dict[str, Any]) -> int:
    """Determine number of IP parts to use"""
    if arguments['-0']:
        return 0
    elif arguments['-1']:
        return 1
    elif arguments['-2']:
        return 2
    elif arguments['-3']:
        return 3
    elif arguments['-4']:
        return 4
    return 2  # Default to 2 parts

def main() -> int:
    """
    Main function to handle hostname and DNS setup.

    Returns:
        int: Exit code (0 for success, non-zero for failure)
    """
    try:
        arguments = parse_arguments()

        if arguments['--debug']:
            print(arguments)

        # Handle prefix
        prefix = arguments['--prefix']
        if arguments['--prefix-tag'] is not None:
            prefix = get_prefix_from_tags(arguments['--prefix-tag'])
            if not prefix:
                return lib.error(2, f"No tag with that name ({arguments['--prefix-tag']})")

        # Handle domain
        domain: Optional[str] = None
        if arguments['--domain']:
            domain = arguments['--domain']
        if arguments['--domain-tag']:
            domain = get_domain_from_tags(arguments['--domain-tag'])
            if not domain:
                return lib.error(2, f"No tag with that name ({arguments['--domain-tag']})")

        if not domain:
            return lib.error(2, "No domain specified")

        # Get IP address
        ip = get_ip(arguments['--public'])

        # Create configuration
        config = HostnameConfig(
            ip=ip,
            prefix=prefix,
            numparts=get_numparts(arguments),
            domain=domain,
            sep=arguments.get('--prefix-sep', '')
        )

        # Generate FQDN
        fqdn = gen_fqdn(config)

        # Handle screen output
        if not arguments['-q']:
            print(fqdn)

        if arguments['--screen-only']:
            return 0

        # Set hostname if requested
        if not arguments['--no-host']:
            if lib.set_hostname(fqdn) != 0:
                return lib.error(3, "Failed to set hostname")

        # Set EC2 Name tag if requested
        if not arguments['--no-ec2-name']:
            lib.set_instance_name(fqdn)

        # Update DNS if requested
        if not arguments['--no-dns']:
            hosted_zone = arguments['--hosted-zone'] or domain
            ttl = int(arguments['--ttl'])
            wait = int(arguments['--wait'])

            try:
                lib.route53_upsert_a_record(
                    domain=hosted_zone,
                    fqdn=fqdn,
                    ip=ip,
                    ttl=ttl,
                    wait=wait
                )
            except Exception as e:
                return lib.error(4, f"Failed to update DNS: {str(e)}")

        return 0

    except KeyboardInterrupt:
        return lib.error(130, "\nOperation cancelled by user")
    except Exception as e:
        return lib.error(1, f"Unexpected error: {str(e)}")

if __name__ == '__main__':
    sys.exit(main())
