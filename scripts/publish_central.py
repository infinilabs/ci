import os
import sys
import time
import base64
import requests
import json

BASE_URL = "https://central.sonatype.com/api/v1/publisher"

def drop_deployment(deployment_id, headers):
    if not deployment_id: return
    print(f"\nDropping deployment: {deployment_id} ...")
    try:
        resp = requests.delete(f"{BASE_URL}/deployment/{deployment_id}", headers=headers)
        if resp.status_code in [200, 204]:
            print("Dropped successfully.")
        else:
            print(f"Drop failed: {resp.status_code} {resp.text}")
    except Exception as e:
        print(f"Drop error: {e}")

def main():
    username = os.environ.get('OSSRH_USERNAME')
    password = os.environ.get('OSSRH_PASSWORD')
    zip_path = os.environ.get('ZIP_FILE_PATH')

    if not all([username, password, zip_path]):
        print("Error: Missing env vars")
        sys.exit(1)

    auth_str = f"{username}:{password}"
    b64_auth = base64.b64encode(auth_str.encode()).decode()
    headers = {"Authorization": f"UserToken {b64_auth}"}

    print(f"Uploading {zip_path}...")
    try:
        with open(zip_path, 'rb') as f:
            resp = requests.post(f"{BASE_URL}/upload", headers=headers, 
                               files={'bundle': f}, 
                               data={'publishingType': 'AUTOMATIC'})
        
        if resp.status_code != 201:
            print(f"Upload Failed: {resp.status_code} - {resp.text}")
            sys.exit(1)
            
        deployment_id = resp.text.strip().replace('"', '')
        print(f"Uploaded. ID: {deployment_id}")

    except Exception as e:
        print(f"Upload Error: {e}")
        sys.exit(1)

    print("Waiting for validation...")
    start_time = time.time()
    consecutive_errors = 0
    
    while True:
        if time.time() - start_time > 300:
            print("\nTimeout.")
            drop_deployment(deployment_id, headers)
            sys.exit(1)

        try:
            status_resp = requests.post(f"{BASE_URL}/status", headers=headers, json={"deploymentId": deployment_id})
            
            if status_resp.status_code == 200:
                consecutive_errors = 0
                data = status_resp.json()
                state = data.get('deploymentState', 'UNKNOWN')
                
                print(f"   Status: {state}")

                if state == 'PUBLISHED':
                    print("\nPUBLISHED Successfully!")
                    sys.exit(0)
                
                elif state == 'FAILED':
                    print("\nFAILED.")
                    print("Errors:", json.dumps(data.get('errors', {}), indent=2))
                    drop_deployment(deployment_id, headers)
                    sys.exit(1)
            else:
                consecutive_errors += 1
                print(f"   HTTP {status_resp.status_code}: {status_resp.text}")
                
                if consecutive_errors >= 5:
                    print("\nToo many API errors. Aborting.")
                    drop_deployment(deployment_id, headers)
                    sys.exit(1)

        except Exception as e:
            print(f"   Exception: {e}")
            consecutive_errors += 1

        time.sleep(10)

if __name__ == "__main__":
    main()