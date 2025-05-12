provider "kubernetes" {
  config_path = "./config.yml"
}

# -var="image=infinilabs/gateway-amd64:1.27.0_NIGHTLY-20240805" -var='k8s_config={cluster="infini.dev",namespace="liukj",domain="ddfsfsdfsdf-192-168-3-27.nip.io",node_port=32727}' -var='instance_type={name="1c1g",cpu="1",memory="1G"}' -var='node={id="aaaa,bbbb",labels={tenant_id="aa",group_id="aaa"}}' -var='configs={server="http://demo.infini.cloud"}'
locals {
  image          = var.image
  k8s_config     = var.k8s_config
  instance_type  = var.instance_type
  node           = var.node
  config_server  = var.configs.server

  name           = "proxy-${local.node.labels.group_id}"
  node_ids       = split(",",local.node.id)
}

resource "kubernetes_pod" "this" {
  for_each = toset(local.node_ids)

  metadata {
    name = "${local.name}-${each.value}"
    namespace = local.k8s_config.namespace
    labels = {
      "infini.cloud/app"     = "runtime"
      "infini.cloud/runtime" = "gateway-proxy"
    }
  }
  spec {
    container {
      name              = "gateway-proxy"
      image             = local.image
      image_pull_policy = "IfNotPresent"

      env {
        name  = "NODE_ID"
        value = each.value
      }
      env {
        name  = "TENANT_ID"
        value = local.node.labels.tenant_id
      }
      env {
        name  = "GROUP_ID"
        value = local.node.labels.group_id
      }
      env {
        name  = "CONFIG_SERVER"
        value = local.config_server
      }
      env {
        name  = "K8S_CLUSTER"
        value = local.k8s_config.cluster
      }
      env {
        name  = "K8S_NAMESPACE"
        value = local.k8s_config.namespace
      }
      env {
        name  = "K8S_CLUSTER_ID"
        value = split("-",local.k8s_config.domain)[0]
      }

      port {
        container_port = 8000
        name           = "http" 
      }
      port {
        container_port = 2900
        name           = "api" 
      }

      resources {
        limits   = {
          cpu    = local.instance_type.cpu
          memory = local.instance_type.memory
        }
        requests = {
          cpu    = local.instance_type.cpu
          memory = local.instance_type.memory
        }
      }

      volume_mount {
        name       = "${local.name}-${each.value}"
        mount_path = "/gateway.yml"
        sub_path   = "gateway.yml"
      }
    }

    volume {
      name = "${local.name}-${each.value}"
      config_map {
        name = "${local.name}-${each.value}"
      }
    }
  }
}

resource "kubernetes_service" "this" {
  metadata {
    name      = local.name
    namespace = local.k8s_config.namespace
    labels    = {
      "infini.cloud/app"     = "runtime"
      "infini.cloud/runtime" = "gateway-proxy"
    }
  }
  spec {
    selector  = {
      "infini.cloud/app"     = "runtime"
      "infini.cloud/runtime" = "gateway-proxy"
    }

    type = "NodePort"
    port {
      port        = 8000
      node_port   = local.k8s_config.node_port
      name        = "http"
    }
  }
}

resource "kubernetes_config_map" "this" {
  for_each = toset(local.node_ids)

  metadata {
    name = "${local.name}-${each.value}"
    namespace = local.k8s_config.namespace
  }
  data = {
    "gateway.yml" = "${file("./config/gateway")}"
  }
}