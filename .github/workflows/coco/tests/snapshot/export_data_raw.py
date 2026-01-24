import os
import json
import ssl
import base64
import urllib.request
import urllib.error

# ================= CONFIGURATION =================
# Easysearch Host (HTTPS)
ES_ENDPOINT = "https://127.0.0.1:9200"
# Credentials
ES_USERNAME = os.getenv("ES_USERNAME", "elastic")
ES_PASSWORD = os.getenv("ES_PASSWORD", "changeme")
# Index Pattern to export
INDEX_PATTERN = "coco*"
# Output Directory
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "repo")
# =============================================

# 1. Setup SSL Context (Ignore self-signed certificate errors)
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

# 2. Setup Basic Auth Headers
auth_str = f"{ES_USERNAME}:{ES_PASSWORD}"
auth_bytes = auth_str.encode("ascii")
base64_auth = base64.b64encode(auth_bytes).decode("ascii")
HEADERS = {
    "Authorization": f"Basic {base64_auth}",
    "Content-Type": "application/json"
}

def es_request(method, endpoint, body=None):
    """
    Helper function to make HTTP requests to Easysearch using standard library.
    """
    url = f"{ES_ENDPOINT}/{endpoint.lstrip('/')}"
    data = json.dumps(body).encode("utf-8") if body else None
    
    req = urllib.request.Request(url, data=data, headers=HEADERS, method=method)
    
    try:
        with urllib.request.urlopen(req, context=ctx) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        print(f"   [HTTP Error] {e.code}: {e.read().decode('utf-8')}")
        return None
    except Exception as e:
        print(f"   [Error] {e}")
        return None

def clean_settings(settings_dict):
    """
    Remove system-generated settings that are not portable (UUIDs, creation dates, etc.)
    """
    if "index" not in settings_dict:
        return settings_dict
    
    idx_cfg = settings_dict["index"]
    # Keys to remove to ensure the schema is portable
    keys_to_remove = ["uuid", "creation_date", "version", "provided_name", "store", "routing", "resize"]
    
    for key in keys_to_remove:
        if key in idx_cfg:
            del idx_cfg[key]
    
    return settings_dict

def main():
    print(f"🚀 Starting export for pattern: {INDEX_PATTERN} -> {OUTPUT_DIR}")
    
    # 1. Get list of indices
    print("🔍 Fetching index list...")
    indices_data = es_request("GET", f"_cat/indices/{INDEX_PATTERN}?format=json&h=index")
    
    if not indices_data:
        print("❌ No indices found or connection failed.")
        return

    index_names = [x['index'] for x in indices_data]
    print(f"📦 Found {len(index_names)} indices: {index_names}\n")

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    for idx in index_names:
        print(f"👉 Processing index: {idx}")
        idx_dir = os.path.join(OUTPUT_DIR, idx)
        os.makedirs(idx_dir, exist_ok=True)

        # --- A. Export Settings and Mappings ---
        meta = es_request("GET", idx)
        if meta and idx in meta:
            original_settings = meta[idx].get("settings", {})
            mappings = meta[idx].get("mappings", {})
            
            # Clean settings
            cleaned_settings = clean_settings(original_settings)
            
            # Build Schema Structure
            schema = {
                "settings": cleaned_settings,
                "mappings": mappings
            }
            
            with open(os.path.join(idx_dir, "schema.json"), "w", encoding="utf-8") as f:
                json.dump(schema, f, ensure_ascii=False, indent=2)
            print("   ✅ Schema saved.")
        
        # --- B. Export Data (Using Scroll API) ---
        scroll_size = 1000
        # Initialize scroll
        init_scroll = es_request("POST", f"{idx}/_search?scroll=1m", {
            "size": scroll_size,
            "query": {"match_all": {}},
            "sort": ["_doc"]
        })

        if not init_scroll:
            print("   ❌ Failed to read data.")
            continue

        scroll_id = init_scroll.get("_scroll_id")
        hits = init_scroll.get("hits", {}).get("hits", [])
        total_docs = 0

        with open(os.path.join(idx_dir, "data.jsonl"), "w", encoding="utf-8") as f:
            while hits:
                for doc in hits:
                    # Write source data (one JSON per line)
                    f.write(json.dumps(doc["_source"], ensure_ascii=False) + "\n")
                    total_docs += 1
                
                # Fetch next batch
                scroll_res = es_request("POST", "_search/scroll", {
                    "scroll": "1m",
                    "scroll_id": scroll_id
                })
                
                if not scroll_res:
                    break
                    
                hits = scroll_res.get("hits", {}).get("hits", [])
                # Update scroll_id if changed
                scroll_id = scroll_res.get("_scroll_id", scroll_id)

        # Clear scroll context
        if scroll_id:
            es_request("DELETE", "_search/scroll", {"scroll_id": scroll_id})

        print(f"   ✅ Data saved: {total_docs} documents.")

    print("\n🎉 All tasks completed!")

if __name__ == "__main__":
    main()