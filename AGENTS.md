# Purpose
Terraform repository containing the code to deploy the load tests for camunda on AWS ECS. 
Note that there are other  other load tests, but they use kubernetes.
This repository attempts at recreating something like that, although in a smaller scale.


# Environments

Each module supports `dev` and `prod` environments. Run commands from the environment subdirectory:

```bash
cd aws/<module>/dev  && make plan    # plan dev
cd aws/<module>/prod && make plan    # plan prod
```

Deploy order: `stable` → `benchmark` → `monitoring` → `load_test`

| Env  | Stable state key                  | Resource prefix pattern       |
|------|-----------------------------------|-------------------------------|
| dev  | `stable/dev/terraform.tfstate`    | `dev-benchmark1`, `dev-monitoring`, `dev-load_test1` |
| prod | `stable/prod/terraform.tfstate`   | `benchmark1`, `monitoring`, `load_test1`             |


# Modules
There are different modules:
- `stable` contains "static" infrastructure that is used by all the other benchmarks.
  - stable VPC that is used to connect to the clusters
  - Container registry to pull images from
- `monitoring` contains a grafana + prometheus services to use for metrics temporarily
- `benchmark` contains code to start a camunda cluster
- `load_test` contains code with the starter/worker to exercise load in the cluster (depends on `benchmark`) 
