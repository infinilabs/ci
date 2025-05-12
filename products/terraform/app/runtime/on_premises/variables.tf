variable "region" {
  type = string
  default = ""
}

variable "image" {
  type = string
  default = ""
}

variable "k8s_config" {
  type = object({
    cluster   = string
    namespace = string
    domain    = string
    node_port = number
  })
  default = {
    cluster = ""
    namespace = ""
    domain = ""
    node_port = 0
  }
}

variable "instance_type" {
  type = object({
    name   = string
    cpu    = string
    memory = string
  })
  default = {
    name = ""
    cpu = ""
    memory = ""
  }
}

variable "volume_size" {
  type = number
  default = 10
}

variable "node" {
  type = object({
    id = string
    labels = object({
      type = string
      tenant_id = string
      group_id = string
    })
  })
  default = {
    id = "test"
    labels = {
      type = "runtime"
      tenant_id = ""
      group_id = "test"
    }
  }
}

variable "configs" {
  type = object({
    server = string
  })
  default = {
    server = ""
  }
}

variable "logging_es" {
  type = object({
    endpoint = string
    username = string
    password = string
  })
  default = {
    endpoint = ""
    username = ""
    password = ""
  }
}

variable "s3" {
  type = object({
    access_key    = string
    access_secret = string
    bucket        = string
    enable        = string
    endpoint      = string
  })
  default = {
    access_key = ""
    access_secret = ""
    bucket = ""
    enable = ""
    endpoint = ""
  }
}