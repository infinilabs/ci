env:
   CLUSTER_PASSWORD: $[[keystore.$[[CLUSTER_ID]]_password]]

elasticsearch:
  - id: $[[TASK_ID]]
    name: $[[TASK_ID]]
    cluster_uuid: $[[CLUSTER_UUID]]
    enabled: true
    distribution: $[[CLUSTER_DISTRIBUTION]]
    version: $[[CLUSTER_VERSION]]
    endpoints: $[[CLUSTER_ENDPOINT]]
    discovery:
      enabled: false
    basic_auth:
      username: $[[CLUSTER_USERNAME]]
      password: $[[CLUSTER_PASSWORD]]
    traffic_control:
      enabled: true
      max_qps_per_node: 100
      max_bytes_per_node: 10485760
      max_connection_per_node: 5

pipeline:

#node level metrics
- auto_start: $[[NODE_LEVEL_TASKS_ENABLED]]
  enabled: $[[NODE_LEVEL_TASKS_ENABLED]]
  keep_running: true
  name: collect_$[[TASK_ID]]_es_node_stats
  retry_delay_in_ms: 10000
  processor:
  - es_node_stats:
      elasticsearch: $[[TASK_ID]]
      labels:
        cluster_id: $[[CLUSTER_ID]]
        cluster_uuid: $[[CLUSTER_UUID]]
        cluster_name: $[[CLUSTER_NAME]]
      when:
        cluster_available: ["$[[TASK_ID]]"]

#node logs
- auto_start: $[[LOG_TASKS_ENABLED]]
  enabled: $[[LOG_TASKS_ENABLED]]
  keep_running: true
  name: collect_$[[TASK_ID]]_es_logs
  retry_delay_in_ms: 10000
  processor:
  - es_logs_processor:
      elasticsearch: $[[TASK_ID]]
      labels:
        cluster_id: $[[CLUSTER_ID]]
        cluster_uuid: $[[CLUSTER_UUID]]
        cluster_name: $[[CLUSTER_NAME]]
      logs_path: $[[NODE_LOGS_PATH]]
      queue_name: logs
      when:
        cluster_available: ["$[[TASK_ID]]"]

#MANAGED: false
