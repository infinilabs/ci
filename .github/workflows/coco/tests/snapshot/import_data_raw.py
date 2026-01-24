import os
import sys
import json
import time
import base64
import ssl
import urllib.request
import urllib.error

# ================= CONFIGURATION =================
# Easysearch URL
ES_ENDPOINT = os.getenv("ES_ENDPOINT", "https://localhost:9200") 
# Credentials
ES_USERNAME = os.getenv("ES_USERNAME", "elastic")
ES_PASSWORD = os.getenv("ES_PASSWORD", "changeme")
# Data input directory
INPUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "repo")

# Pattern to clean before restoring (Ensures a completely clean slate)
# This matches your requirement to delete "coco_*" before starting
CLEANUP_PATTERN = "coco_*" 
# =============================================

# 1. Setup SSL Context (Ignore self-signed certificate errors)
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

# 2. Setup Basic Auth Headers
auth_str = f"{ES_USERNAME}:{ES_PASSWORD}"
auth_bytes = auth_str.encode("ascii")
base64_auth = base64.b64encode(auth_bytes).decode("ascii")

COMMON_HEADERS = {
    "Authorization": f"Basic {base64_auth}",
    "Content-Type": "application/json"
}

def es_request(method, endpoint, body=None):
    """
    Standard HTTP request wrapper with Auth and SSL support.
    """
    url = f"{ES_ENDPOINT}/{endpoint.lstrip('/')}"
    data = json.dumps(body).encode("utf-8") if body else None
    
    req = urllib.request.Request(url, data=data, headers=COMMON_HEADERS, method=method)
    
    try:
        with urllib.request.urlopen(req, context=ctx) as response:
            return json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        # Return error details for handling (e.g., 404 is fine during delete)
        return {"error": e.code, "msg": e.read().decode('utf-8')}
    except Exception as e:
        print(f"Error: {e}")
        return None

def wait_for_es():
    """
    Wait for Easysearch to be healthy.
    """
    print(f"Waiting for Easysearch at {ES_ENDPOINT}...")
    url = f"{ES_ENDPOINT}/_cluster/health"
    req = urllib.request.Request(url, headers=COMMON_HEADERS, method="GET")
    
    for i in range(30):
        try:
            with urllib.request.urlopen(req, context=ctx) as response:
                if response.status == 200:
                    print("Easysearch is up!")
                    return
        except Exception:
            time.sleep(1)
    print("Timeout waiting for Easysearch")

def main():
    wait_for_es()
    
    # --- STEP 0: Global Cleanup ---
    # Delete all indices matching the pattern to ensure a clean slate.
    print(f"🧹 Performing global cleanup for pattern: {CLEANUP_PATTERN}...")
    res = es_request("DELETE", CLEANUP_PATTERN)
    
    if res and "acknowledged" in res and res["acknowledged"]:
        print(f"   ✅ Deleted all indices matching '{CLEANUP_PATTERN}'")
    elif res and "error" in res and res["error"] == 404:
        print(f"   ℹ️ No existing indices matched '{CLEANUP_PATTERN}' (Clean start)")
    else:
        print(f"   ⚠️ Cleanup response: {res}")

    # --- STEP 1: Restore from Files ---
    if not os.path.exists(INPUT_DIR):
        print(f"❌ Data directory not found: {INPUT_DIR}")
        sys.exit(1)

    # Iterate over exported index directories
    for idx_name in os.listdir(INPUT_DIR):
        idx_path = os.path.join(INPUT_DIR, idx_name)
        if not os.path.isdir(idx_path):
            continue
            
        print(f"📦 Restoring index: {idx_name}...")
        
        # A. Restore Schema (Settings & Mappings)
        schema_path = os.path.join(idx_path, "schema.json")
        if os.path.exists(schema_path):
            with open(schema_path, "r", encoding="utf-8") as f:
                schema = json.load(f)
            
            # Optimization for CI: Force replicas to 0
            if "settings" in schema and "index" in schema["settings"]:
                schema["settings"]["index"]["number_of_replicas"] = 0

            # Create new index (No need to delete individual index, we did global cleanup)
            res = es_request("PUT", idx_name, schema)
            if res and "error" in res:
                print(f"   ❌ Create Error: {res}")
                continue # Skip data load if creation failed
        
        # B. Bulk Load Data
        data_path = os.path.join(idx_path, "data.jsonl")
        if os.path.exists(data_path):
            bulk_body = []
            doc_count = 0
            
            with open(data_path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if not line: 
                        continue
                        
                    # Bulk format: metadata line + source line
                    meta = json.dumps({"index": {"_index": idx_name}})
                    bulk_body.append(meta)
                    bulk_body.append(line)
                    doc_count += 1
                    
                    # Send batch every 1000 lines (500 documents)
                    if len(bulk_body) >= 1000:
                        body_str = "\n".join(bulk_body) + "\n"
                        
                        bulk_headers = COMMON_HEADERS.copy()
                        bulk_headers["Content-Type"] = "application/x-ndjson"

                        req = urllib.request.Request(
                            f"{ES_ENDPOINT}/_bulk", 
                            data=body_str.encode('utf-8'), 
                            headers=bulk_headers, 
                            method="POST"
                        )
                        urllib.request.urlopen(req, context=ctx)
                        bulk_body = []
                        print(f"   Indexed batch... ({doc_count} docs so far)")

                # Process remaining documents
                if bulk_body:
                    body_str = "\n".join(bulk_body) + "\n"
                    bulk_headers = COMMON_HEADERS.copy()
                    bulk_headers["Content-Type"] = "application/x-ndjson"
                    req = urllib.request.Request(
                        f"{ES_ENDPOINT}/_bulk", 
                        data=body_str.encode('utf-8'), 
                        headers=bulk_headers, 
                        method="POST"
                    )
                    urllib.request.urlopen(req, context=ctx)
            
            print(f"   ✅ Done restoring {idx_name}.")

if __name__ == "__main__":
    main()