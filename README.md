# swarmy

A collection of boto based scripts (mostly) that are useful for running as part
of user metadata scripts on AWS EC2, either when autoscaling, or just during
instance creation, or as periodic maintenance tasks. These scripts are designed
to be run FROM an instance, but they may also be useful for running on AWS
Lambda.

WARNING: These scripts are pretty quick and dirty. Cleanups and suggestions
welcome.

## How to use

Copy the script `boostrap.sh` into your instance metadata. It will create a
virtualenv, download this repo, run setup.py, and then call a glue script of
your choosing.

### Prerequisites

The bootstrap script and several of the provided stage2 scripts depend on
system packages that may not be in the base system you have selected. It is
suggested that you use cloud-init's cloud-config yaml format to install them.
See `cloudconfig.yml` for an example. Make sure you include hardware enabling
packages here (e.g., nvme-cli). A script (`cloudmultipart.py`) has been
provided to assemble various cloud-init directives into a single file to be
posted as AWS User Data (or similar). Run it as follows:
`python cloudmultipart.py cloudconfig.yml:cloud-config bootstrap.sh:x-shellscript > multipart.txt`
Note that the text/ part of the content-type header is provided for you by the
script.

The `bootstrap.sh` script provided by swarmy requires virtualenv, curl, and
pip. We also suggest installing the development package for libyaml.

### Variables that affect the bootstrap script

There are a number of variables that will affect the behavior of the canned
bootstrap.sh script. Of course you are free to provide your own bootstrap
script instead.

 * `GIT_BRANCH`: specify this variable to check out a swarmy branch other than
   master
 * `NEXT_SCRIPT`: Specify this variable to change which script gets run next.
   It can point to something on the instance, or something inside this repo, or
   even something on S3 or https.
 * `HOSTNAME_ARGS`: The arguments to pass to `dynamic_hostname` (described
   below). You must provide at least the `--domain` or `--domain-tag` argument.
 * `SWARMYDIR`: A location where Swarmy is able to store information on the
   stages that have been run, as well as allow rudimentary message passing
   using text files. Defaults to `/root/.swarmy`

### Sample S3 profile to load these and other environment variables from S3

Set the `SETTINGS_URL` environment variable in the bootstrap script to load and
source a file locally, over http(s), or from s3. For s3 retrieval this should
be formatted like a s3 url used by `aws s3` commands (e.g.,
s3://crunchio-autoscale/settings.profile)

```shell
# Treat like a .profile ...
NEXT_SCRIPT=${NEXT_SCRIPT:-swarmy/scripts/stage2.sh}
HOSTNAME_ARGS=${HOSTNAME_ARGS:-"-2 --domain-tag=Domain --prefix-tag=aws:autoscaling:groupName --wait 10"}
JENKINS_BASE=${JENKINS_BASE:-https://ci.crunch.io/}
JENKINS_USER=user@example.com:API_key
```

These files can be loaded from http/https, S3, or anywhere on the system. If no
URL protocol is given, the script is "sourced" from the local system. If a
relative path is provided, it is relative to root's homedir.

Note that for S3 settings, the instance must be defined with an IAM role, or
the bootstrap script must otherwise set up credentials to make the AWS API
request.

As part of that IAM role, if you wish to set up DNS, you'll need a policy that
grants that right to the IAM Role assigned. Similarly if you'd like to update
the instance tags, you'll need those rights too.

A full policy might look like this:

```javascript
// Note 1: break this up into several distinct policies to ease reuse
// Note 2: Remove comments before using in the Policy editor
{
    "Version": "2012-10-17",
    "Statement": [
        // This allows tag listing and creation on instances in a given region
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "ec2:DescribeTags",
                "ec2:DescribeInstances"
            ],
            "Resource": "arn:aws:ec2:eu-west-1:910774676937:instance/*"
        },
        /* The next section adds rights to read any ec2 data (useful for
           retrieving scaling group and instance info)
          */
        {
          "Effect": "Allow",
          "Action": "ec2:Describe*",
          "Resource": "*"
        },
        {
          "Effect": "Allow",
          "Action": "elasticloadbalancing:Describe*",
          "Resource": "*"
        },
        {
          "Effect": "Allow",
          "Action": [
            "cloudwatch:ListMetrics",
            "cloudwatch:GetMetricStatistics",
            "cloudwatch:Describe*"
          ],
          "Resource": "*"
        },
        {
          "Effect": "Allow",
          "Action": "autoscaling:Describe*",
          "Resource": "*"
        },
        // Rights to update route53 for a specific zone
        {
            "Action": [
                "route53:ChangeResourceRecordSets",
                "route53:GetHostedZone",
                "route53:ListResourceRecordSets"
            ],
            "Effect": "Allow",
            "Resource": [
                "arn:aws:route53:::hostedzone/Z2L387X0621IN6"
            ]
        },
        // Also need to be able to enumerate all the zones
        {
            "Action": [
                "route53:ListHostedZones"
            ],
            "Effect": "Allow",
            "Resource": [
                "*"
            ]
        },
        /* Allow read only access to the s3 bucket that will contain
           additional secrets for enabling access to software repos, or web
           callback to trigger additional setup/configuration
          */
        {
            "Effect": "Allow",
            "Action": [
                "s3:Get*",
                "s3:List*"
            ],
            "Resource": [
                "arn:aws:s3:::crunchio-autoscale",
                "arn:aws:s3:::crunchio-autoscale/*"
            ]
        }

 
    ]
}
```

## Scripts Available

We've written a number of scripts that may make your life easier.

In `bootstrap.sh` the variable `NEXT_SCRIPT` should be set a ` ` (space)
delineated list of scripts to run, this allows chaining scripts together:

```shell
NEXT_SCRIPT="swarmy/scripts/stage2.sh swarmy/scripts/prephemeral.sh swarmy/scripts/mountephemeral.sh"
```

For example will run `stage2.sh`, `prepephemeral.sh` and then
`mountephemeral.sh` in that order from the swarmy directory relative to root's $HOME.

These files can be loaded from http/https, S3, or anywhere on the system. If no
URL protocol is given, the script is "sourced" from the local system. If a
relative path is provided, it is relative to root's homedir.

### stage2.sh

Sets the hostname based on

 * The private-ip (or public ip) of the instance
 * The `Domain` tag
 * The `aws:autoscaling:groupName` tag
 * The `Name` tag

Once the hostname is determined, sets the hostname via the hostname command,
and registers the hostname in Route53. Can also wait for the record to be
propagated before exiting.

#### Prerequisites

None once swarmy is pip installed.

### prepephemeral.sh

This will using the aws command grab information from EC2 regarding the
available ephemeral drives in the system. If there is more than one, it will
create an md raid array to be able to utilize it as a single disk.

#### Prerequisites

mdadm (plus aws-cli and curl installed with swarmy in `bootstrap.sh`).

### mountephemeral.sh

Using the output from `prepephemeral.sh` (a file dropped in
`$SWARMYDIR/ephemeralldev`) it will create a new file system and then mount it,
as well as add the appropriate fstab entries. See the top of the
`mountephemeral.sh` for environment variables that can modify the scratch space
mapped.

#### Prerequisites

The userspace programs for the file system you've chosen (e.g., xfsprogs, e2fsprogs)

### dockerthinpool.sh

Using the output from `prepephemeral.sh` (a file dropped in
`$SWARMYDIR/ephemeraldev`) it will create a new LVM volume group and create a
thinpool for the express purpose of using it with Docker. It will also create a
smaller logical volume that may be used for an ephemeral mount.

Run `mountephemeral.sh` after `dockerthinpool.sh` to set up the "scratch"
logical volume:

```shell
NEXT_SCRIPT="${NEXT_SCRIPT:+${NEXT_SCRIPT} }prepephemeral.sh dockerthinpool.sh mountephemeral.sh"
```

#### Prerequisites

lvm2 and device-mapper-persistent-data

### Launch configuration update

At Crunch.io, we use an ansible playbook to create and manage our autoscaling
groups and launch configurations.

## Debugging bootstrap script

Look for script log files in /var/log/cloud-init-output.log and swarmy itself
redirects output into `$SWARMYDIR/log.stdout` and `$SWARMYDIR/log.stderr`
