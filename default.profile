# A default setup using 2 octets from the IPv4 address, the Domain and
# NamePrefix instance tags for naming
HOSTNAME_ARGS="-1 --domain-tag=Domain --prefix-tag=NamePrefix"
NEXT_SCRIPT="swarmy/scripts/stage2.sh swarmy/scripts/prepephemeral.sh swarmy/scripts/mountephemeral.sh"

