# runner: {
#   reset_context: true,
#   default_endpoint: "$[[env.CONSOLE_ENDPOINT]]",
# }

# // user login
POST /account/login
{"userName": "$[[env.CONSOLE_USERNAME]]","password": "$[[env.CONSOLE_PASSWORD]]","type": "account"}
# register: [
#   {access_token: "_ctx.response.body_json.access_token"}
# ],
# assert: {
#   _ctx.response.status: 200
# }

GET /instance/_search?size=20&keyword=&application=agent
# request: {
#   headers: [
#     {authorization: "Bearer $[[access_token]]"}
#   ],
#   disable_header_names_normalizing: false
# },
# register: [
#   {agent_id: "_ctx.response.body_json.hits.hits.0._id"}
# ],
# assert: {
#   _ctx.response.status: 200
# }

POST /elasticsearch/infini_default_system_cluster/_proxy?method=GET&path=%2F.infini_instance%2F_search
{"_source": "_id","query": {"term": {"application.name": {"value": "agent"}}}}
# request: {
#   headers: [
#     {authorization: "Bearer $[[access_token]]"}
#   ],
#   disable_header_names_normalizing: false
# },
# assert: {
#   _ctx.response.status: 200
# }

GET /instance/$[[agent_id]]/node/_discovery
# request: {
#   headers: [
#     {authorization: "Bearer $[[access_token]]"}
#   ],
#   disable_header_names_normalizing: false
# },
# assert: {
#   _ctx.response.status: 200
# }

GET $[[env.ES_ENDPOINT]]/.infini_instance/_search
# assert: {
#   _ctx.response.status: 200
# }

GET $[[env.ES_ENDPOINT]]/.infini_configs/_doc/system_ingest_config_yml
# assert: {
#   _ctx.response.status: 200
# }

POST $[[env.ES_ENDPOINT]]/.infini_metrics/_refresh
# assert: {
#   _ctx.response.status: 200
# }

GET $[[env.ES_ENDPOINT]]/.infini_metrics/_count
{"query":{"term":{"metadata.name":{"value":"shard_stats"}}}}
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.count: >=1
# }

GET $[[env.ES_ENDPOINT]]/.infini_cluster/_search
# assert: {
#   _ctx.response.status: 200
# }

POST $[[env.ES_ENDPOINT]]/.infini_metrics/_search
{"query":{"term":{"metadata.name":{"value":"shard_stats"}}}}
# assert: {
#   _ctx.response.status: 200
# }

POST $[[env.ES_ENDPOINT]]/.infini_logs/_refresh
# assert: {
#   _ctx.response.status: 200
# }

POST $[[env.ES_ENDPOINT]]/.infini_logs/_count
{"query":{"bool":{"must":[{"term":{"agent.id":{"value":"$[[agent_id]]"}}}]}}}
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.count: >=1
# }

POST $[[env.ES_ENDPOINT]]/.infini_metrics/_count
{"query":{"bool":{"must":[{"term":{"agent.id":{"value":"$[[agent_id]]"}}},{"term":{"metadata.name":{"value":"shard_stats"}}}]}}}
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.count: >=1
# }

POST /elasticsearch/infini_default_system_cluster/_proxy?method=GET&path=%2F.infini_metrics%2F_count
{"query":{"bool":{"must":[{"term":{"metadata.name":{"value":"shard_stats"}}}]}}}
# request: {
#   headers: [
#     {authorization: "Bearer $[[access_token]]"}
#   ],
#   disable_header_names_normalizing: false
# },
# assert: {
#   _ctx.response.status: 200
# }

