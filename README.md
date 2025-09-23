## SSO Login Helper Script
1. clone the repo.
```
git clone git@github.com:kumumedia/kumu-devops-cli-tools.git
```

2. you may now start/test the script
note that the `dot space` script name is intentional so that the environment varibles will be exported to the current shell
```
. ./connect_kumu.sh
```
or
```
. $(pwd)/connect_kumu.sh
```

you may also confirm by invoking below. this should list S3 buckets under the account
```
aws s3 ls
```