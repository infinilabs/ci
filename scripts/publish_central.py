import os
import sys
import time
import base64
import requests
import json

BASE_URL = "https://central.sonatype.com/api/v1/publisher"

def drop_deployment(deployment_id, headers):
    """Clean up failed/stuck deployment"""
    if not deployment_id:
        return
    print(f"\n🗑️ Attempting to drop deployment: {deployment_id} ...")
    try:
        del_url = f"{BASE_URL}/deployment/{deployment_id}"
        resp = requests.delete(del_url, headers=headers)
        if resp.status_code in [200, 204]:
            print("✅ Deployment dropped successfully.")
        else:
            print(f"⚠️ Failed to drop deployment: {resp.status_code} {resp.text}")
    except Exception as e:
        print(f"⚠️ Error dropping deployment: {e}")

def main():
    username = os.environ.get('OSSRH_USERNAME')
    password = os.environ.get('OSSRH_PASSWORD')
    zip_path = os.environ.get('ZIP_FILE_PATH')

    if not username or not password or not zip_path:
        print("Error: Missing env vars")
        sys.exit(1)

    # Auth
    auth_str = f"{username}:{password}"
    b64_auth = base64.b64encode(auth_str.encode()).decode()
    headers = {"Authorization": f"UserToken {b64_auth}"}

    # 1. Upload
    print(f"🚀 Uploading {zip_path}...")
    try:
        with open(zip_path, 'rb') as f:
            # publishingType=AUTOMATIC
            resp = requests.post(f"{BASE_URL}/upload", headers=headers, 
                               files={'bundle': f}, 
                               data={'publishingType': 'AUTOMATIC'})
        
        if resp.status_code != 201:
            print(f"❌ Upload Failed: {resp.status_code} - {resp.text}")
            sys.exit(1)
            
        deployment_id = resp.text.strip().replace('"', '')
        print(f"✅ Upload Successful. ID: {deployment_id}")

    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

    # 2. Check Status Loop
    print("⏳ Waiting for validation...")
    start_time = time.time()
    timeout_seconds = 600 # 10 mins
    
    last_response = None

    while True:
        # Timeout Check
        if time.time() - start_time > timeout_seconds:
            print("\n❌ Timeout waiting for deployment.")
            print(f"Last API Response: {json.dumps(last_response, indent=2)}")
            drop_deployment(deployment_id, headers)
            sys.exit(1)

        try:
            # Check Status
            status_resp = requests.post(f"{BASE_URL}/status", headers=headers, json={"deploymentId": deployment_id})
            
            if status_resp.status_code == 200:
                data = status_resp.json()
                last_response = data
                state = data.get('deploymentState', 'UNKNOWN')
                
                print(f"   Status: {state}")

                if state == 'PUBLISHED':
                    print("\n🎉 Deployment PUBLISHED Successfully!")
                    sys.exit(0)
                
                elif state == 'FAILED':
                    print("\n❌ Deployment FAILED.")
                    print("Errors:")
                    print(json.dumps(data.get('errors', {}), indent=2))
                    drop_deployment(deployment_id, headers)
                    sys.exit(1)
                
                elif state == 'UNKNOWN':
                    pass 
            else:
                print(f"   HTTP {status_resp.status_code} checking status...")

        except Exception as e:
            print(f"   Check error: {e}")

        time.sleep(15)

if __name__ == "__main__":
    main()