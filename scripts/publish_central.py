import os
import sys
import time
import base64
import requests

def main():
    username = os.environ.get('OSSRH_USERNAME')
    password = os.environ.get('OSSRH_PASSWORD')
    zip_path = os.environ.get('ZIP_FILE_PATH')

    if not username or not password or not zip_path:
        print("Error: Missing environment variables (OSSRH_USERNAME, OSSRH_PASSWORD, ZIP_FILE_PATH)")
        sys.exit(1)

    auth_str = f"{username}:{password}"
    b64_auth = base64.b64encode(auth_str.encode()).decode()
    headers = {"Authorization": f"UserToken {b64_auth}"}

    print(f"🚀 Uploading {zip_path} to Central Portal...")
    upload_url = "https://central.sonatype.com/api/v1/publisher/upload"
    
    try:
        with open(zip_path, 'rb') as f:
            files = {'bundle': f}
            data = {'publishingType': 'AUTOMATIC'}
            resp = requests.post(upload_url, headers=headers, files=files, data=data)
            
        if resp.status_code != 201:
            print(f"❌ Upload Failed: {resp.status_code} - {resp.text}")
            sys.exit(1)
            
        deployment_id = resp.text.strip().replace('"', '')
        print(f"✅ Upload Successful. ID: {deployment_id}")

    except Exception as e:
        print(f"❌ Network Error during upload: {e}")
        sys.exit(1)

    print("⏳ Waiting for validation and publishing...")
    status_url = "https://central.sonatype.com/api/v1/publisher/status"
    
    start_time = time.time()
    timeout_seconds = 600

    while True:
        if time.time() - start_time > timeout_seconds:
            print("❌ Timeout waiting for deployment status.")
            sys.exit(1)

        try:
            status_resp = requests.post(status_url, headers=headers, json={"deploymentId": deployment_id})
            status_data = status_resp.json()
            state = status_data.get('deploymentState', 'UNKNOWN')

            print(f"   Current State: {state}")

            if state == 'PUBLISHED':
                print("🎉 Deployment PUBLISHED Successfully!")
                sys.exit(0)
            
            if state == 'FAILED':
                print("❌ Deployment FAILED!")
                errors = status_data.get('errors', [])
                for err in errors:
                    print(f"   - {err}")
                sys.exit(1)

        except Exception as e:
            print(f"   Warning: Check status failed ({e}), retrying...")

        time.sleep(10)

if __name__ == "__main__":
    main()