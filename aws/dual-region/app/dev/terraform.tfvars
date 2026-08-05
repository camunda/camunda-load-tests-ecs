# The app state has no static per-environment config: every non-default input is
# run-specific and is injected via -var from dev/Makefile (see EXTRA_TF_VARS) —
# infra_state_path (derived from BENCHMARK_NAME) and the optional camunda_image
# override. Everything else comes from the defaults in ../variables.tf.
# This file must still exist because shared.mk always passes -var-file.
