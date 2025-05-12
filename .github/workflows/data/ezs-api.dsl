# runner: {
#   reset_context: true,
#   default_endpoint: "$[[env.ES_ENDPOINT]]",
# }

DELETE /test_index

# // Test Case 1: Create an index with default settings
PUT /test_index
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0
  }
}
# // Assert: Ensure index creation is successful
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

DELETE /test_mapping_index
# // Test Case 2: Create an index with specific mappings
PUT /test_mapping_index
{
  "mappings": {
    "properties": {
      "user": { "type": "text" },
      "age": { "type": "integer" },
      "join_date": { "type": "date" },
      "is_active": { "type": "boolean" }
    }
  }
}
# // Assert: Ensure the mapping is set correctly
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 3: Insert a single document
POST /test_mapping_index/_doc/1
{
  "user": "john_doe",
  "age": 30,
  "join_date": "2025-04-23T10:00:00",
  "is_active": true
}
# // Assert: Ensure document insertion is successful
# assert: {
#   _ctx.response.status: 201,
#   _ctx.response.body_json._id: "1"
# }

# // Test Case 4: Bulk insert multiple documents
POST /test_mapping_index/_bulk
{ "index": { "_id": 2 } }
{ "user": "alice_smith", "age": 25, "join_date": "2025-04-22T09:30:00", "is_active": false }
{ "index": { "_id": 3 } }
{ "user": "bob_jones", "age": 35, "join_date": "2025-04-21T15:45:00", "is_active": true }
{ "index": { "_id": 4 } }
{ "user": "carol_white", "age": 28, "join_date": "2025-04-20T12:00:00", "is_active": true }
# // Assert: Ensure bulk insert works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.items: >=3
# }

# // Test Case 5: Search with a match query
POST /test_mapping_index/_search
{
  "query": {
    "match": { "user": "john_doe" }
  }
}
# // Assert: Ensure match query returns correct result
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 1
# }

# // Test Case 6: Search with a term query
POST /test_mapping_index/_search
{
  "query": {
    "term": { "is_active": true }
  }
}
# // Assert: Ensure term query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: >=1
# }

# // Test Case 7: Search with a range query
POST /test_mapping_index/_search
{
  "query": {
    "range": {
      "age": { "gte": 30, "lte": 40 }
    }
  }
}
# // Assert: Ensure range query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 2
# }

# // Test Case 8: Search with a boolean query
POST /test_mapping_index/_search
{
  "query": {
    "bool": {
      "must": [
        { "match": { "user": "john_doe" } },
        { "range": { "age": { "gte": 25, "lte": 40 } } }
      ]
    }
  }
}
# // Assert: Ensure bool query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 1
# }

# // Test Case 9: Search with sorting by a field (age)
POST /test_mapping_index/_search
{
  "query": {
    "match_all": {}
  },
  "sort": [
    { "age": { "order": "asc" } }
  ]
}
# // Assert: Ensure sorting by age works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.hits.0._source.age: 25
# }

# // Test Case 10: Search with sorting by date field
POST /test_mapping_index/_search
{
  "query": {
    "match_all": {}
  },
  "sort": [
    { "join_date": { "order": "desc" } }
  ]
}
# // Assert: Ensure sorting by join_date works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.hits.0._source.join_date: "2025-04-23T10:00:00"
# }

# // Test Case 11: Aggregation with terms aggregation
POST /test_mapping_index/_search
{
  "aggs": {
    "user_count": {
      "terms": { "field": "user" }
    }
  }
}
# // Assert: Ensure aggregation works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.aggregations.user_count.buckets: >=1
# }

# // Test Case 12: Aggregation with date histogram
POST /test_mapping_index/_search
{
  "aggs": {
    "join_date_histogram": {
      "date_histogram": {
        "field": "join_date",
        "interval": "day"
      }
    }
  }
}
# // Assert: Ensure date histogram aggregation works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.aggregations.join_date_histogram.buckets: >=1
# }

# // Test Case 13: Nested aggregation
POST /test_mapping_index/_search
{
  "aggs": {
    "nested_users": {
      "nested": {
        "path": "user_details"
      },
      "aggs": {
        "user_count": {
          "terms": { "field": "user_details.user" }
        }
      }
    }
  }
}
# // Assert: Ensure nested aggregation works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.aggregations.nested_users.user_count.buckets: >=1
# }

# // Test Case 14: Insert a geo_point document
POST /geo_test_index/_doc/1
{
  "location": { "lat": 40.7128, "lon": -74.0060 }
}
# // Assert: Ensure geo_point is inserted correctly
# assert: {
#   _ctx.response.status: 201,
#   _ctx.response.body_json._id: "1"
# }

# // Test Case 15: Geo distance query
POST /geo_test_index/_search
{
  "query": {
    "geo_distance": {
      "distance": "100km",
      "location": { "lat": 40.7128, "lon": -74.0060 }
    }
  }
}
# // Assert: Ensure geo query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: >=1
# }

# // Test Case 16: Update document by ID
POST /test_mapping_index/_update/1
{
  "doc": { "age": 32 }
}
# // Assert: Ensure document update is successful
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.result: "updated"
# }

# // Test Case 17: Delete document by ID
DELETE /test_mapping_index/_doc/1
# // Assert: Ensure document is deleted successfully
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.result: "deleted"
# }

# // Test Case 18: Bulk delete documents
POST /test_mapping_index/_bulk
{ "delete": { "_id": 2 } }
{ "delete": { "_id": 3 } }
{ "delete": { "_id": 4 } }
# // Assert: Ensure bulk delete is successful
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.items: >=3
# }

# // Test Case 19: Search with missing field
POST /test_mapping_index/_search
{
  "query": {
    "exists": {
      "field": "missing_field"
    }
  }
}
# // Assert: Ensure query with missing field returns no results
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 0
# }

# // Test Case 20: Delete an index
DELETE /test_mapping_index
# // Assert: Ensure index is deleted successfully
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 21: Search with exists query
POST /test_mapping_index/_search
{
  "query": {
    "exists": {
      "field": "age"
    }
  }
}
# // Assert: Ensure exists query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: >=1
# }

# // Test Case 22: Search with match phrase query
POST /test_mapping_index/_search
{
  "query": {
    "match_phrase": {
      "user": "john_doe"
    }
  }
}
# // Assert: Ensure match phrase query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 1
# }

# // Test Case 23: Use filter to limit results
POST /test_mapping_index/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "is_active": true } },
        { "range": { "age": { "gte": 30 } } }
      ]
    }
  }
}
# // Assert: Ensure filtered query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 2
# }

# // Test Case 24: Search with a fuzzy query
POST /test_mapping_index/_search
{
  "query": {
    "fuzzy": {
      "user": "john_doe"
    }
  }
}
# // Assert: Ensure fuzzy query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 1
# }

# // Test Case 25: Search with prefix query
POST /test_mapping_index/_search
{
  "query": {
    "prefix": {
      "user": "john"
    }
  }
}
# // Assert: Ensure prefix query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 1
# }

# // Test Case 26: Search with wildcard query
POST /test_mapping_index/_search
{
  "query": {
    "wildcard": {
      "user": "john*"
    }
  }
}
# // Assert: Ensure wildcard query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 1
# }

# // Test Case 27: Search with regex query
POST /test_mapping_index/_search
{
  "query": {
    "regexp": {
      "user": "jo.*"
    }
  }
}
# // Assert: Ensure regex query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 1
# }

# // Test Case 28: Search with a range query on date field
POST /test_mapping_index/_search
{
  "query": {
    "range": {
      "join_date": {
        "gte": "2025-04-20T00:00:00",
        "lte": "2025-04-23T00:00:00"
      }
    }
  }
}
# // Assert: Ensure range query on date works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 4
# }

# // Test Case 29: Aggregation with sum aggregation
POST /test_mapping_index/_search
{
  "aggs": {
    "total_age": {
      "sum": { "field": "age" }
    }
  }
}
# // Assert: Ensure sum aggregation works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.aggregations.total_age.value: 120
# }

# // Test Case 30: Aggregation with avg aggregation
POST /test_mapping_index/_search
{
  "aggs": {
    "avg_age": {
      "avg": { "field": "age" }
    }
  }
}
# // Assert: Ensure average aggregation works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.aggregations.avg_age.value: 30
# }

# // Test Case 31: Aggregation with max aggregation
POST /test_mapping_index/_search
{
  "aggs": {
    "max_age": {
      "max": { "field": "age" }
    }
  }
}
# // Assert: Ensure max aggregation works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.aggregations.max_age.value: 35
# }

# // Test Case 32: Aggregation with min aggregation
POST /test_mapping_index/_search
{
  "aggs": {
    "min_age": {
      "min": { "field": "age" }
    }
  }
}
# // Assert: Ensure min aggregation works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.aggregations.min_age.value: 25
# }

# // Test Case 33: Aggregation with cardinality aggregation
POST /test_mapping_index/_search
{
  "aggs": {
    "unique_users": {
      "cardinality": { "field": "user" }
    }
  }
}
# // Assert: Ensure cardinality aggregation works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.aggregations.unique_users.value: 4
# }

# // Test Case 34: Index with custom settings (number of replicas)
PUT /custom_settings_index
{
  "settings": {
    "number_of_shards": 2,
    "number_of_replicas": 1
  }
}
# // Assert: Ensure custom settings are applied
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 35: Use a custom analyzer for text fields
PUT /custom_analyzer_index
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "custom_tokenizer": {
          "type": "pattern",
          "pattern": "\\W"
        }
      },
      "analyzer": {
        "custom_analyzer": {
          "type": "custom",
          "tokenizer": "custom_tokenizer"
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "description": { "type": "text", "analyzer": "custom_analyzer" }
    }
  }
}
# // Assert: Ensure custom analyzer is created
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 36: Search with custom analyzer
POST /custom_analyzer_index/_search
{
  "query": {
    "match": { "description": "test phrase" }
  }
}
# // Assert: Ensure search with custom analyzer works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 1
# }

# // Test Case 37: Create an alias for an index
POST /_aliases
{
  "actions": [
    {
      "add": {
        "index": "test_mapping_index",
        "alias": "test_alias"
      }
    }
  ]
}
# // Assert: Ensure alias creation is successful
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 38: Search with alias
POST /test_alias/_search
{
  "query": {
    "match": { "user": "john_doe" }
  }
}
# // Assert: Ensure search with alias works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 1
# }

# // Test Case 39: Delete alias
POST /_aliases
{
  "actions": [
    {
      "remove": {
        "index": "test_mapping_index",
        "alias": "test_alias"
      }
    }
  ]
}
# // Assert: Ensure alias deletion is successful
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 40: Create an index with warmers
PUT /index_with_warmers
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0
  },
  "warmers": {
    "my_warmer": {
      "query": {
        "match_all": {}
      }
    }
  }
}
# // Assert: Ensure index with warmers is created
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 41: Get index settings
GET /test_mapping_index/_settings
# // Assert: Ensure index settings can be retrieved
# assert: {
#   _ctx.response.status: 200
# }

# // Test Case 42: Get index mapping
GET /test_mapping_index/_mapping
# // Assert: Ensure index mapping can be retrieved
# assert: {
#   _ctx.response.status: 200
# }

# // Test Case 43: Refresh index
POST /test_mapping_index/_refresh
# // Assert: Ensure index is refreshed
# assert: {
#   _ctx.response.status: 200
# }

# // Test Case 44: Search with multiple filters
POST /test_mapping_index/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "active" } },
        { "range": { "age": { "gte": 30 } } }
      ]
    }
  }
}
# // Assert: Ensure multi-filter query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 2
# }

# // Test Case 45: Check cluster health
GET /_cluster/health
# // Assert: Ensure cluster health is ok
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.status: "green"
# }

# // Test Case 46: Create a new index with specific settings and mappings
PUT /custom_index
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 2
  },
  "mappings": {
    "properties": {
      "name": { "type": "text" },
      "age": { "type": "integer" }
    }
  }
}
# // Assert: Ensure index is created successfully
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 47: Use multi-search API for multiple queries
POST /_msearch
{ }
POST /_msearch
{
  "query": { "match": { "status": "active" } }
}
# // Assert: Ensure multi-search works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.responses.length: 2
# }

# // Test Case 48: Use index template
PUT /_index_template/my_template
{
  "index_patterns": ["logs-*"],
  "template": {
    "mappings": {
      "properties": {
        "timestamp": { "type": "date" },
        "log_level": { "type": "keyword" }
      }
    }
  }
}
# // Assert: Ensure index template is created successfully
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 49: Create a custom field with type "keyword"
PUT /custom_keyword_field
{
  "mappings": {
    "properties": {
      "category": { "type": "keyword" }
    }
  }
}
# // Assert: Ensure custom keyword field is created
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 50: Create an index with dynamic templates
PUT /index_with_dynamic_templates
{
  "mappings": {
    "dynamic_templates": [
      {
        "strings": {
          "match_mapping_type": "string",
          "mapping": { "type": "text" }
        }
      }
    ]
  }
}
# // Assert: Ensure dynamic templates are created
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }


# // Test Case 51: Create an index with custom settings for refresh interval
PUT /index_with_refresh
{
  "settings": {
    "number_of_shards": 1,
    "number_of_replicas": 0,
    "refresh_interval": "5s"
  }
}
# // Assert: Ensure the refresh interval is applied
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 52: Create an index with custom analyzer for a specific field
PUT /custom_analyzer_for_field_index
{
  "settings": {
    "analysis": {
      "analyzer": {
        "standard_analyzer": {
          "type": "standard",
          "stopwords": "_english_"
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "title": { "type": "text", "analyzer": "standard_analyzer" }
    }
  }
}
# // Assert: Ensure custom analyzer is applied
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 53: Delete an index
DELETE /index_with_refresh
# // Assert: Ensure the index is deleted
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 54: Update a document using script
POST /test_mapping_index/_update/1
{
  "script": {
    "source": "ctx._source.age += 1",
    "lang": "painless"
  }
}
# // Assert: Ensure document is updated successfully
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.result: "updated"
# }

# // Test Case 55: Delete a document by ID
DELETE /test_mapping_index/_doc/1
# // Assert: Ensure document is deleted
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.result: "deleted"
# }

# // Test Case 56: Bulk insert documents
POST /test_mapping_index/_bulk
{ "index": { "_id": 1 } }
{ "user": "john_doe", "age": 30 }
{ "index": { "_id": 2 } }
{ "user": "jane_doe", "age": 25 }
# // Assert: Ensure documents are inserted successfully
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.errors: false
# }

# // Test Case 57: Use nested field query
POST /test_mapping_index/_search
{
  "query": {
    "nested": {
      "path": "address",
      "query": {
        "bool": {
          "must": [
            { "match": { "address.city": "New York" } }
          ]
        }
      }
    }
  }
}
# // Assert: Ensure nested query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 1
# }

# // Test Case 58: Create an index with mappings for geo-point data
PUT /geo_index
{
  "mappings": {
    "properties": {
      "location": {
        "type": "geo_point"
      }
    }
  }
}
# // Assert: Ensure geo_point field is created
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 59: Insert a document with geo-point data
POST /geo_index/_doc/1
{
  "location": {
    "lat": 40.7128,
    "lon": -74.0060
  }
}
# // Assert: Ensure geo-point data is inserted
# assert: {
#   _ctx.response.status: 201,
#   _ctx.response.body_json._id: "1"
# }

# // Test Case 60: Query geo-point data with a bounding box
POST /geo_index/_search
{
  "query": {
    "geo_bounding_box": {
      "location": {
        "top_left": { "lat": 40.8, "lon": -74.2 },
        "bottom_right": { "lat": 40.6, "lon": -73.8 }
      }
    }
  }
}
# // Assert: Ensure geo_bounding_box query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 1
# }

# // Test Case 61: Check if a document exists by ID
HEAD /test_mapping_index/_doc/1
# // Assert: Ensure document exists
# assert: {
#   _ctx.response.status: 200
# }

# // Test Case 62: Check if a document does not exist by ID
HEAD /test_mapping_index/_doc/100
# // Assert: Ensure document does not exist
# assert: {
#   _ctx.response.status: 404
# }

# // Test Case 63: Use script to update document field
POST /test_mapping_index/_update/1
{
  "script": {
    "source": "ctx._source.age = params.age",
    "params": { "age": 35 }
  }
}
# // Assert: Ensure document is updated successfully
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.result: "updated"
# }

# // Test Case 64: Use match all query
POST /test_mapping_index/_search
{
  "query": {
    "match_all": {}
  }
}
# // Assert: Ensure match_all query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: >=1
# }

# // Test Case 65: Create an index with custom analyzer and tokenizer
PUT /custom_analyzer_tokenizer_index
{
  "settings": {
    "analysis": {
      "tokenizer": {
        "custom_tokenizer": {
          "type": "whitespace"
        }
      },
      "analyzer": {
        "custom_analyzer": {
          "type": "custom",
          "tokenizer": "custom_tokenizer"
        }
      }
    }
  },
  "mappings": {
    "properties": {
      "content": {
        "type": "text",
        "analyzer": "custom_analyzer"
      }
    }
  }
}
# // Assert: Ensure custom analyzer and tokenizer are applied
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.acknowledged: true
# }

# // Test Case 66: Query with terms query
POST /test_mapping_index/_search
{
  "query": {
    "terms": {
      "status": ["active", "pending"]
    }
  }
}
# // Assert: Ensure terms query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: >=1
# }

# // Test Case 67: Search with script score
POST /test_mapping_index/_search
{
  "query": {
    "function_score": {
      "query": {
        "match": { "user": "john_doe" }
      },
      "functions": [
        {
          "script_score": {
            "script": "Math.log(2 + doc['age'].value)"
          }
        }
      ]
    }
  }
}
# // Assert: Ensure script score query works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 1
# }

# // Test Case 68: Multi-index search
POST /test_mapping_index,test_mapping_index2/_search
{
  "query": {
    "match": { "user": "john_doe" }
  }
}
# // Assert: Ensure multi-index search works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.hits.total.value: 1
# }

# // Test Case 69: Get document by ID
GET /test_mapping_index/_doc/1
# // Assert: Ensure document is retrieved
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json._id: "1"
# }

# // Test Case 70: Search with aggregation and filtering
POST /test_mapping_index/_search
{
  "query": {
    "bool": {
      "filter": [
        { "term": { "status": "active" } },
        { "range": { "age": { "gte": 30 } } }
      ]
    }
  },
  "aggs": {
    "average_age": {
      "avg": { "field": "age" }
    }
  }
}
# // Assert: Ensure aggregation with filter works
# assert: {
#   _ctx.response.status: 200,
#   _ctx.response.body_json.aggregations.average_age.value: 32.5
# }
