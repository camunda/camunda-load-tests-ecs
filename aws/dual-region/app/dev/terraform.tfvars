# All app inputs are injected via -var from dev/Makefile (see EXTRA_TF_VARS).
# MySQL build: image bundles the MySQL JDBC driver (not in the stock image).
camunda_image = "030846071718.dkr.ecr.eu-west-1.amazonaws.com/aurora-mysql-test/camunda:8.10-SNAPSHOT-mysql"
