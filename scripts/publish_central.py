import os
import sys
import time
import base64
import requests
import json

# ================= Config =================
BASE_URL = "https://central.sonatype.com/api/v1/publisher"
DEBUG = os.environ.get('DEBUG', 'false').lower() == 'true'

# Force unbuffered output for CI
sys.stdout.reconfigure(line_buffering=True)

def debug_log(msg):
    if DEBUG:
        print(f"\033[90m[DEBUG] {msg}\033[0m")

def safe_headers(headers):
    """Return headers with masked sensitive info"""
    safe = headers.copy()
    if 'Authorization' in safe:
        safe['Authorization'] = 'UserToken ******'
    return safe

def drop_deployment(deployment_id, headers):
    if not deployment_id: 
        return
    url = f"{BASE_URL}/deployment/{deployment_id}"
    print(f"\n🗑️  [DELETE] {url}")
    
    if DEBUG:
        debug_log(f"Headers: {safe_headers(headers)}")

    try:
        resp = requests.delete(url, headers=headers)
        if DEBUG:
            debug_log(f"Response ({resp.status_code}): {resp.text}")

        if resp.status_code in [200, 204]:
            print("✅ Dropped successfully.")
        else:
            print(f"⚠️ Drop failed: {resp.status_code} {resp.text}")
    except Exception as e:
        print(f"⚠️ Drop error: {e}")

def main():
    username = os.environ.get('OSSRH_USERNAME')
    password = os.environ.get('OSSRH_PASSWORD')
    zip_path = os.environ.get('ZIP_FILE_PATH')

    if not all([username, password, zip_path]):
        print("Error: Missing env vars (OSSRH_USERNAME, OSSRH_PASSWORD, ZIP_FILE_PATH)")
        sys.exit(1)

    auth_str = f"{username}:{password}"
    b64_auth = base64.b64encode(auth_str.encode()).decode()
    headers = {"Authorization": f"UserToken {b64_auth}"}

    # ================= 1. Upload =================
    upload_url = f"{BASE_URL}/upload"
    print(f"🚀 [POST] {upload_url}")
    print(f"   File: {os.path.basename(zip_path)}")
    
    if DEBUG:
        debug_log(f"Headers: {safe_headers(headers)}")
        debug_log("Payload: publishingType=AUTOMATIC")

    try:
        with open(zip_path, 'rb') as f:
            resp = requests.post(upload_url, headers=headers, 
                               files={'bundle': f}, 
                               data={'publishingType': 'AUTOMATIC'})
        
        if DEBUG:
            debug_log(f"Response Status: {resp.status_code}")
            debug_log(f"Response Body: {resp.text}")

        if resp.status_code != 201:
            print(f"❌ Upload Failed: {resp.status_code} - {resp.text}")
            sys.exit(1)
            
        deployment_id = resp.text.strip().replace('"', '')
        print(f"✅ Uploaded. ID: {deployment_id}")

    except Exception as e:
        print(f"❌ Upload Error: {e}")
        sys.exit(1)

    # Cool down
    print("💤 Waiting 15s for server to process...")
    time.sleep(15)

    # ================= 2. Check Status =================
    status_url = f"{BASE_URL}/status?id={deployment_id}"
    print(f"⏳ [POST] {status_url} (ID: {deployment_id})")
    
    start_time = time.time()
    consecutive_errors = 0
    
    while True:
        if time.time() - start_time > 600: # 10 mins
            print("\n❌ Timeout.")
            drop_deployment(deployment_id, headers)
            sys.exit(1)

        try:
            status_body = {"deploymentId": deployment_id}
            status_resp = requests.post(status_url, headers=headers, json=status_body)
            
            if DEBUG:
                debug_log(f"Check Status: {status_resp.status_code}")
                debug_log(f"Body: {status_resp.text}")

            if status_resp.status_code == 200:
                consecutive_errors = 0
                data = status_resp.json()
                state = data.get('deploymentState', 'UNKNOWN')
                
                print(f"   Status: {state}")

                if state == 'PUBLISHED':
                    print("\n🎉 PUBLISHED Successfully!")
                    sys.exit(0)
                
                elif state == 'FAILED':
                    print("\n❌ FAILED.")
                    print("Errors:", json.dumps(data.get('errors', {}), indent=2))
                    drop_deployment(deployment_id, headers)
                    sys.exit(1)
            else:
                consecutive_errors += 1
                print(f"   ⚠️ HTTP {status_resp.status_code}: {status_resp.text}")
                
                if consecutive_errors >= 5:
                    print("\n❌ Too many API errors (500). Aborting.")
                    drop_deployment(deployment_id, headers)
                    sys.exit(1)

        except Exception as e:
            print(f"   ⚠️ Exception: {e}")
            consecutive_errors += 1

        time.sleep(10)

if __name__ == "__main__":
    main()