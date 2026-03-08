# Shared secrets for seed-system k8s workloads (controller, host-agent).
#
# Each node's defaultSopsFile must contain these keys in its own
# secrets/seed-system.yaml (encrypted for all seed node age keys).
{ config, ... }:
{
  sops.secrets."seed/controller/gh-webhook-secret" = {
    sopsFile = ../secrets/seed-system.yaml;
  };
}
