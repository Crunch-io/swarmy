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

 * `GIT_BRANCH`: specify this variable to check out a swarmy branch other than master
 * `NEXT_SCRIPT`: Specify this variable to change which script gets run next. It can point to something on the instance, or something inside this repo, or even something on S3 or https.
 * `HOSTNAME_ARGS`: The arguments to pass to `dynamic_hostname` (described below). You must provide at least the `--domain` or `--domain-tag` argument.
 * `USE_IAM`: If you launch your instances with an IAM Role (Highly Recommended), it will be used instead of credentials, even if provided. (Do we want this?)

### Sample S3 profile to load these and other environment variables from S3
Set the SETTINGS_URL environment variable in the bootstrap script to load and source a file from s3. This should be formatted like a s3 url used by `aws s3` commands (e.g., s3://crunchio-autoscale/settings.profile)

```shell
NEXT_SCRIPT=${NEXT_SCRIPT:-stage2.sh}
HOSTNAME_ARGS=${HOSTNAME_ARGS:-"-2 --domain-tag=Domain --prefix-tag=aws:autoscaling:groupName"}
JENKINS_BASE=${JENKINS_BASE:-https://ci.crunch.io/}
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
Calls the Jenkins API to trigger some sort of action. (Used instead of Lambda, for example).

### update\_launch\_configuration (TODO)
Updates the specified launch configuration with: the latest AMI image in a series, the latest bootstrap.sh metadata, etc.
