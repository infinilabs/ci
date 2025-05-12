provider "kubernetes" {
  config_path = "./config.yml"
}

locals {
  region         = var.region
  image          = var.image  #infinilabs/gateway-amd64:1.27.0_NIGHTLY-20240805
  k8s_config     = var.k8s_config
  instance_type  = var.instance_type
  volume_size    = var.volume_size
  node           = var.node
  configs        = var.configs
  logging_es     = var.logging_es
  s3             = var.s3


  name          = local.node.labels.type
  node_ids      = split(",",local.node.id)
  config_file   = local.name == "runtime" ? local.s3.enable == "true" ? "gateway_s3" : "gateway" : "gateway_proxy"
  port_info     = local.name == "gateway" ? [{"name": "http", "port": 8000, "node_port": local.k8s_config.node_port},{"name": "api", "port": 2900}] : [{"name": "api", "port": 2900}]
}

resource "kubernetes_stateful_set" "this" {
  for_each = toset(local.node_ids)

  metadata {
    name = "${local.name}-${each.value}"
    namespace = local.k8s_config.namespace

    labels = {
      "infini.cloud/app"           = "runtime"
      "infini.cloud/runtime"       = local.name == "gateway" ? "gateway-proxy" : "${local.name}-${each.value}"
      "infini.cloud/runtime-group" = local.node.labels.group_id
    }
  }
  spec {
    replicas = local.name == "gateway" ? 2 : 1
    service_name = local.name == local.name == "gateway" ? "gateway-proxy" : "${local.name}-${each.value}"
    selector {
      match_labels = {
        "infini.cloud/app"           = "runtime"
        "infini.cloud/runtime"       = local.name == "gateway" ? "gateway-proxy" : "${local.name}-${each.value}"
        "infini.cloud/runtime-group" = local.node.labels.group_id
      }
    }
    template {
      metadata {
        labels = {
          "infini.cloud/app"           = "runtime"
          "infini.cloud/runtime"       = local.name == "gateway" ? "gateway-proxy" : "${local.name}-${each.value}"
          "infini.cloud/runtime-group" = local.node.labels.group_id
        }
      }
      spec {
        container {
          name              = "gateway"
          image             = local.image
          image_pull_policy = "IfNotPresent"

          command = ["sh", "-c", "if [ ! -d '/app/config' ]; then mkdir -p /app/config; fi && ./gateway"]
  
          env {
            name  = "NODE_ID"
            value = each.value
          }
          env {
            name  = "NODE_ENDPOINT"
            value = local.name == "gateway" ? "http://gateway-proxy.${local.k8s_config.domain}:${local.k8s_config.node_port}" : "http://${local.name}-${each.value}.${local.k8s_config.domain}:${local.k8s_config.node_port}"
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
          env {
            name  = "CONFIG_SERVER"
            value = local.configs.server
          }
          env {
            name  = "LOGGING_ES_ENDPOINT"
            value = local.logging_es.endpoint
          }
          env {
            name  = "LOGGING_ES_USER"
            value = local.logging_es.username
          }
          env {
            name  = "LOGGING_ES_PASS"
            value = local.logging_es.password
          }
          env {
            name  = "S3_ENABLE"
            value = local.s3.enable
          }
          env {
            name  = "S3_BUCKET"
            value = local.s3.bucket
          }
          env {
            name  = "S3_ENDPOINT"
            value = local.s3.endpoint
          }
          env {
            name  = "S3_ACCESS_KEY"
            value = local.s3.access_key
          }
          env {
            name  = "S3_ACCESS_SECRET"
            value = local.s3.access_secret
          }

          dynamic "port" {
            for_each = local.port_info

            content {
              name           = port.value.name
              container_port = port.value.port
            }
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
            name       = "${local.name}-${each.value}-config"
            mount_path = "/gateway.yml"
            sub_path   = "gateway.yml"
          }
          volume_mount {
            name       = "${local.name}-${each.value}-data"
            mount_path = "/app"
          }
        }

        volume {
          name = "${local.name}-${each.value}-config"
          config_map {
            name = "${local.name}-${each.value}-config"
          }
        }
      }
    }

    volume_claim_template {
      metadata {
        name = "${local.name}-${each.value}-data"
      }
      spec {
        access_modes = ["ReadWriteOnce"]
        resources {
          requests = {
            "storage" = "${local.volume_size}G"
          }
        }
      }
    }
    persistent_volume_claim_retention_policy {
      when_deleted = "Delete"
    }
  }
}

resource "kubernetes_service" "this" {
  for_each = toset(local.node_ids)

  metadata {
    name      = local.name == "gateway" ? "gateway-proxy" : "${local.name}-${each.value}"
    namespace = local.k8s_config.namespace
    labels    = {
      "infini.cloud/app"           = "runtime"
      "infini.cloud/runtime"       = local.name == "gateway" ? "gateway-proxy" : "${local.name}-${each.value}"
      "infini.cloud/runtime-group" = local.node.labels.group_id
    }
  }

  spec {
    selector  = {
      "infini.cloud/app"           = "runtime"
      "infini.cloud/runtime"       = local.name == "gateway" ? "gateway-proxy" : "${local.name}-${each.value}"
      "infini.cloud/runtime-group" = local.node.labels.group_id
    }

    type = local.node.labels.type == "runtime" ? "ClusterIP" : "NodePort"
    
    dynamic "port" {
      for_each = local.port_info

      content {
        name      = port.value.name
        port      = port.value.port
        # node_port = lookup(port.value, "node_port", null)
        node_port = try(port.value.node_port, 0)
      }
    }
  }
}

resource "kubernetes_config_map" "this" {
  for_each = toset(local.node_ids)

  metadata {
    name = "${local.name}-${each.value}-config"
    namespace = local.k8s_config.namespace
  }
  data = {
    "gateway.yml" = "${file("./config/${local.config_file}")}"
  }
}