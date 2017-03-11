# swarmy
A collection of boto based scripts (mostly) that are useful for running as part
of user metadata scripts on AWS EC2, either when autoscaling, or just during
instance creation, or as periodic maintenance tasks. These scripts are designed
to be run FROM an instance, but they may also be useful for running on AWS
Lambda.

WARNING: These scripts are pretty quick and dirty. Cleanups and suggestions
welcome.

## How to use
Copy the script `boostrap-<distro>.sh` into your instance metadata. It will
download this repo, run setup.py, and then call a glue script of your choosing.

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

### Sample S3 profile to load these and other environment variables from S3
Set the SETTINGS_URL environment variable in the bootstrap script to load and
source a file locally, over http(s), or from s3. For s3 retrieval this should
be formatted like a s3 url used by `aws s3` commands (e.g.,
s3://crunchio-autoscale/settings.profile)

```shell
# Treat like a .profile ...
NEXT_SCRIPT=${NEXT_SCRIPT:-stage2.sh}
HOSTNAME_ARGS=${HOSTNAME_ARGS:-"-2 --domain-tag=Domain --prefix-tag=aws:autoscaling:groupName --wait 10"}
JENKINS_BASE=${JENKINS_BASE:-https://ci.crunch.io/}
JENKINS_USER=user@example.com:API_key
```

Note that for S3 settings, the instance must be defined with an IAM role, or
the bootstrap script must otherwise set up credentials to make the AWS API
request.

As part of that IAM role, if you wish to set up DNS, you'll need a policy that grants that right to the IAM Role assigned. Similarly if you'd like to update the instance tags, you'll need those rights too.

A full policy might look like this:

```json
# Note 1: break this up into several distinct policies to ease reuse
# Note 2: Remove comments before using in the Policy editor
{
    "Version": "2012-10-17",
    "Statement": [
        # This allows tag listing and creation on instances in a given
        # region
        {
            "Effect": "Allow",
            "Action": [
                "ec2:CreateTags",
                "ec2:DescribeTags",
                "ec2:DescribeInstances"
            ],
            "Resource": "arn:aws:ec2:eu-west-1:910774676937:instance/*"
        },
        # The next section adds rights to read any ec2 data (useful for
        # retrieving scaling group and instance info)
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
        # Rights to update route53 for a specific zone
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
        # Also need to be able to enumerate all the zones
        {
            "Action": [
                "route53:ListHostedZones"
            ],
            "Effect": "Allow",
            "Resource": [
                "*"
            ]
        },
        # Allow read only access to the s3 bucket that will contain
        # additional secrets for enabling access to software repos, or web
        # callback to trigger additional setup/configuration
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

### dynamic\_hostname
Sets the hostname based on

 * The private-ip (or public ip) of the instance
 * The `Domain` tag
 * The `aws:autoscaling:groupName` tag
 * The `Name` tag

Once the hostname is determined, sets the hostname via the hostname command,
and registers the hostname in Route53. Can also wait for the record to be
propagated before exiting.

### trigger\_jenkins\_job (TODO)
Calls the Jenkins API to trigger some sort of action. (Used instead of Lambda,
for example).

### Launch configuration update
At Crunch.io, we use an ansible playbook to create and manage our autoscaling
groups and launch configurations.
