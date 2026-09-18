---
name: ecs-bastion
description: Open an SSM bastion + port-forward to a private ECS Fargate service (Camunda actuator 9600, REST API 8080, gRPC 26500, Aurora 3306/5432) in this repo's AWS deployments. Use when you need to curl or connect to a service that has no public endpoint, in either the single-region (aws/stable, aws/load_test) or dual-region (aws/dual-region) setups.
---

# ECS bastion + port forwarding

All snippets are written for **bash** (4+) and also work in zsh. If your login shell is
something else, run them with `bash -c '...'`.

Deployments here run ECS Fargate tasks in **private subnets with no public endpoint**. To reach
them from a laptop you launch a throwaway EC2 instance, register it with SSM, and port-forward
through it. There is no Terraform bastion resource — do it with the AWS CLI.

## 0. Prerequisites

- `session-manager-plugin` installed locally.
- Instance profile **`camunda-dr-bastion-ssm`** (policy `AmazonSSMManagedInstanceCore`) already
  exists account-wide and is reused for every bastion. Recreate only if missing:
  ```bash
  aws iam create-role --role-name camunda-dr-bastion-ssm \
    --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}'
  aws iam attach-role-policy --role-name camunda-dr-bastion-ssm \
    --policy-arn arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore
  aws iam create-instance-profile --instance-profile-name camunda-dr-bastion-ssm
  aws iam add-role-to-instance-profile --instance-profile-name camunda-dr-bastion-ssm --role-name camunda-dr-bastion-ssm
  ```

## 1. Pick region, cluster, and target task IP

Get task IPs from **ECS, not Cloud Map** — Cloud Map `list-instances` returns stale/cycled IPs.

```bash
REGION=us-east-1                       # dual-region r1; eu-west-1 = r0; single-region: whatever you deployed
aws ecs list-clusters --region $REGION --output json
CLUSTER=dev-camunda-dr-r1-cluster      # single-region e.g. camunda-us-east-1-cluster

# bash 4+ (and zsh): read the arns into an array, expand quoted
read -r -a TASKS <<< "$(aws ecs list-tasks --region $REGION --cluster $CLUSTER --query 'taskArns[]' --output text)"
aws ecs describe-tasks --region $REGION --cluster $CLUSTER --tasks "${TASKS[@]}" \
  --query 'tasks[].{g:group,ip:attachments[0].details[?name==`privateIPv4Address`]|[0].value,s:lastStatus,h:healthStatus,sub:attachments[0].details[?name==`subnetId`]|[0].value}' \
  --output table
```

`--tasks "${TASKS[@]}"` is the portable form: in **bash** a bare `$TASKS` expands to only the
first element, and in **zsh** an unquoted string parameter is not word-split at all — both give
`Invalid identifier: Unexpected number of separators` or a length error. Use the array.

Pick a `RUNNING`/`HEALTHY` task IP and note its `VpcId`:
```bash
VPC=$(aws ec2 describe-subnets --region $REGION --subnet-ids <subnet-from-table> --query 'Subnets[0].VpcId' --output text)
```

## 2. Launch the bastion

**Always use a dedicated SG and a private subnet.**

- The VPC **default SG has its egress rules stripped** (`IpPermissionsEgress: []`) and there are no
  SSM VPC endpoints → an instance in the default SG never registers with SSM (`PingStatus: None`).
  A freshly created SG gets allow-all egress, which is what you want.
- **Private** subnet: has a NAT gateway (SSM registration works without a public IP) *and* the
  VPC-peering / transit-gateway routes to the other region. A **public** subnet has no peer-CIDR
  route, so cross-region traffic (e.g. Aurora writer in the other region) is silently blackholed
  via the IGW — connections just hang with no RST.

```bash
SUBNET=<private subnet id — reuse the subnet of the task you found above>
SG=$(aws ec2 create-security-group --region $REGION --group-name camunda-bastion-$(date +%s) \
      --description "temp bastion egress" --vpc-id $VPC --query GroupId --output text)
aws ec2 create-tags --region $REGION --resources $SG --tags Key=Name,Value=camunda-bastion

AMI=$(aws ssm get-parameter --region $REGION \
      --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
      --query Parameter.Value --output text)   # AL2023 ships curl

INSTANCE=$(aws ec2 run-instances --region $REGION --image-id $AMI --instance-type t3.micro \
  --subnet-id $SUBNET --no-associate-public-ip-address --security-group-ids $SG \
  --iam-instance-profile Name=camunda-dr-bastion-ssm \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=camunda-bastion}]' \
  --query 'Instances[0].InstanceId' --output text)

# wait until Online (usually <1 min)
aws ssm describe-instance-information --region $REGION \
  --filters "Key=InstanceIds,Values=$INSTANCE" --query 'InstanceInformationList[0].PingStatus' --output text
```

Ingress to the target is normally already open: the Camunda SG
(`<prefix>-camunda-ports`) allows 8080/9600/26500-26502/3306/5432 from the whole VPC CIDR.
Verify with `aws ec2 describe-security-groups --group-ids <camunda-ports-sg> --query 'SecurityGroups[0].IpPermissions'`.

## 3. Port-forward (one session per port)

```bash
IP=10.60.64.124   # target task private IP
for P in 9600 8080; do
  nohup aws ssm start-session --region $REGION --target $INSTANCE \
    --document-name AWS-StartPortForwardingSessionToRemoteHost \
    --parameters "{\"host\":[\"$IP\"],\"portNumber\":[\"$P\"],\"localPortNumber\":[\"$P\"]}" \
    > /tmp/ssm-$P.log 2>&1 &
done
sleep 10; cat /tmp/ssm-*.log
```

Then curl locally:
```bash
curl -s localhost:9600/actuator/health | jq .
curl -s localhost:8080/v2/topology | jq .
```

Alternative without forwarding: run commands on the bastion itself
```bash
aws ssm send-command --region $REGION --instance-ids $INSTANCE \
  --document-name AWS-RunShellScript --parameters commands="curl -s http://$IP:9600/actuator/health"
```

### Secrets via send-command
Passing a DB password inline: wrap it in **single** quotes (`DB_PW='...'`). Generated passwords
contain `$` (`override_special = "!#$%^()-_=+[]{}:?"`); inside double quotes the remote shell
expands it and you get a silent `Access denied ... (using password: YES)`. Build the JSON with
`jq -n --arg cmd "$CMD" '{commands: [$cmd]}'`.

## 4. Tear down (always)

```bash
pkill -f 'ssm start-session'                   # stops the port-forward sessions
aws ec2 terminate-instances --region $REGION --instance-ids $INSTANCE
aws ec2 wait instance-terminated --region $REGION --instance-ids $INSTANCE
aws ec2 delete-security-group --region $REGION --group-id $SG
```
Leave the `camunda-dr-bastion-ssm` instance profile in place for reuse.

## Ports cheat sheet
| Port | Service |
|------|---------|
| 9600 | Camunda actuator / management (`/actuator/health`, `/actuator/cluster`) |
| 8080 | Orchestration cluster REST API (`/v2/topology`) |
| 26500-26502 | gRPC gateway / broker command + internal |
| 3306 / 5432 | Aurora MySQL / PostgreSQL writer |
| 9200 | OpenSearch |
| 9090 | Prometheus |
