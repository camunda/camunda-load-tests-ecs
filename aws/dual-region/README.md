# Dual-region Camunda load test

This folder deploys a Camunda cluster across two AWS regions and runs the ECS
load test against region 0. The deployment is split into three Terraform
states:

```text
vpc -> infra -> app -> load_test
```

The default regions are `eu-west-1` (region 0 / primary) and `us-east-1`
(region 1 / secondary). The dual-region stack uses basic authentication, so
load-test traffic must use REST. gRPC with basic authentication is not
supported by the current load-test client setup.

## GitHub Actions

The easiest way to create the complete stack is GitHub Actions:

1. Open **Actions** in GitHub.
2. Select **Deploy Dual-Region Load Test**.
3. Click **Run workflow**.
4. Choose `postgresql` or `mysql`.
5. Provide the region 0 REST endpoint, including the scheme, for example:
   `http://<region-0-alb-dns>:80`.

The workflow deploys VPC, infra, app, and load test in order. It sets
`DUAL_REGION=true`, configures the load test to prefer REST, and reads the
admin password from the infra state.

## Manual deployment

Run the following prerequisite states first if they are not already deployed:

```bash
cd aws/stable/dev && make deploy
cd aws/stable/us-east-1 && make deploy
```

Choose a short name for the run. It is used in all state keys and AWS resource
names. The examples below use `camunda-dr`.

### 1. VPC

```bash
cd aws/dual-region/vpc/dev
make deploy BENCHMARK_NAME=camunda-dr
```

### 2. Infra

`DATABASE_ENGINE` can be `postgresql` (the default) or `mysql`:

```bash
cd aws/dual-region/infra/dev
make deploy \
  BENCHMARK_NAME=camunda-dr \
  DATABASE_ENGINE=postgresql
```

For MySQL:

```bash
make deploy \
  BENCHMARK_NAME=camunda-dr \
  DATABASE_ENGINE=mysql
```

### 3. App

For PostgreSQL, the default Camunda image is used:

```bash
cd aws/dual-region/app/dev
make deploy BENCHMARK_NAME=camunda-dr
```

The MySQL build requires an image containing the MySQL JDBC driver:

```bash
make deploy \
  BENCHMARK_NAME=camunda-dr \
  CAMUNDA_IMAGE=030846071718.dkr.ecr.eu-west-1.amazonaws.com/aurora-mysql-test/camunda:8.10-SNAPSHOT-mysql
```

The app must be deployed only after the infra state has completed. The app
Makefile automatically reads:

```text
dual-region/infra/dev-camunda-dr.tfstate
```

### 4. Load test

The load test is deployed in the existing region 0 stable VPC/ECS cluster.
Use the load-test module from its environment directory:

```bash
cd aws/load_test/dev
make apply \
  BENCHMARK_NAME=camunda-dr-r0 \
  DUAL_REGION=true \
  DUAL_REGION_INFRA_STATE_KEY=dual-region/infra/dev-camunda-dr.tfstate \
  REST_ADDRESS=http://<region-0-alb-dns>:80 \
  PREFER_REST_OVER_GRPC=true \
  CAMUNDA_AUTH_USERNAME=admin \
  CAMUNDA_AUTH_PASSWORD_SECRET_ARN=<region-0-password-secret-arn> \
  CAMUNDA_AUTH_PASSWORD_KMS_KEY_ARN=<region-0-kms-key-arn> \
  FORCE_NEW_DEPLOYMENT=true
```

The region 0 ALB endpoint can be obtained from the infra state:

```bash
cd aws/dual-region/infra
terraform output -raw region_0_alb_endpoint
```

The admin password secret and its KMS key can be resolved with:

```bash
SECRET_ARN=$(terraform output -raw admin_user_password_secret_region_0_arn)
KMS_ARN=$(aws secretsmanager describe-secret \
  --secret-id "$SECRET_ARN" \
  --query KmsKeyId \
  --output text)
```

Use those values for `CAMUNDA_AUTH_PASSWORD_SECRET_ARN` and
`CAMUNDA_AUTH_PASSWORD_KMS_KEY_ARN`.

### Previous command

The historical command was:

```bash
make apply DUAL_REGION=true \
  CAMUNDA_HOST=orchestration-cluster.dev-camunda-dr-r0-oc.service.local \
  PREFER_REST_OVER_GRPC=false \
  FORCE_NEW_DEPLOYMENT=true
```

This remains useful for an unprotected cluster or for reproducing an older
run. For the current dual-region setup, do not use `PREFER_REST_OVER_GRPC=false`
with basic authentication. Use `REST_ADDRESS`, `PREFER_REST_OVER_GRPC=true`,
and the admin authentication variables shown above.

## Destroying a run

Destroy in reverse dependency order:

```bash
cd aws/load_test/dev
make destroy \
  BENCHMARK_NAME=camunda-dr-r0 \
  DUAL_REGION=true \
  DUAL_REGION_INFRA_STATE_KEY=dual-region/infra/dev-camunda-dr.tfstate

cd ../../dual-region/app/dev
make destroy BENCHMARK_NAME=camunda-dr

cd ../infra/dev
make destroy BENCHMARK_NAME=camunda-dr

cd ../vpc/dev
make destroy BENCHMARK_NAME=camunda-dr
```

The stable VPC states are shared infrastructure and should not be destroyed
as part of an individual load-test run.
