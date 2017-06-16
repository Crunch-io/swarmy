# A default setup using 2 octets from the IPv4 address, the Domain and
# NamePrefix instance tags for naming
HOSTNAME_ARGS="-2 --domain-tag=Domain --prefix-tag=NamePrefix"
NEXT_SCRIPT="s3://crunchio-autoscale/stage2.sh s3://crunchio-autoscale/mountephemeral.sh"

