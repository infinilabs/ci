#!/usr/bin/env python3
"""
Maven Central Deployment Cleanup Script

Lists all deployments and optionally cleans up failed/stuck ones.

Usage:
  # List all deployments
  python3 cleanup_central.py --list
  
  # Clean up specific deployment
  python3 cleanup_central.py --drop DEPLOYMENT_ID
  
  # Clean up all FAILED deployments
  python3 cleanup_central.py --clean-failed
  
  # Clean up all non-PUBLISHED deployments (FAILED + VALIDATING + PUBLISHING)
  python3 cleanup_central.py --clean-all

Environment variables:
  OSSRH_USERNAME - Maven Central username
  OSSRH_PASSWORD - Maven Central password (or token)
"""

import os
import sys
import requests
import json
import argparse
from datetime import datetime

BASE_URL = "https://central.sonatype.com/api/v1/publisher"

def get_auth_header():
    """Get authorization header from environment"""
    username = os.environ.get('OSSRH_USERNAME')
    password = os.environ.get('OSSRH_PASSWORD')
    
    if not username or not password:
        print("❌ Error: OSSRH_USERNAME and OSSRH_PASSWORD must be set")
        sys.exit(1)
    
    import base64
    creds = base64.b64encode(f"{username}:{password}".encode()).decode()
    return {'Authorization': f'UserToken {creds}'}

def list_deployments():
    """List all deployments"""
    headers = get_auth_header()
    
    # Note: Maven Central API might not have a list endpoint
    # We'll try the status endpoint without ID to see if it lists all
    url = f"{BASE_URL}/deployments"
    
    print(f"📋 Fetching deployments from Maven Central...")
    print(f"🔗 {url}")
    
    try:
        resp = requests.get(url, headers=headers)
        
        if resp.status_code == 200:
            deployments = resp.json()
            
            if not deployments:
                print("\n✅ No deployments found")
                return []
            
            print(f"\n📦 Found {len(deployments)} deployment(s):\n")
            print(f"{'ID':<40} {'State':<15} {'Name':<30}")
            print("=" * 90)
            
            for dep in deployments:
                dep_id = dep.get('deploymentId', 'unknown')
                state = dep.get('deploymentState', 'unknown')
                name = dep.get('deploymentName', 'unknown')
                
                # Color code by state
                if state == 'PUBLISHED':
                    state_display = f"\033[32m{state}\033[0m"  # Green
                elif state == 'FAILED':
                    state_display = f"\033[31m{state}\033[0m"  # Red
                elif state == 'PUBLISHING':
                    state_display = f"\033[33m{state}\033[0m"  # Yellow
                else:
                    state_display = state
                
                print(f"{dep_id:<40} {state_display:<24} {name:<30}")
            
            return deployments
        
        elif resp.status_code == 404:
            print("\n⚠️  List endpoint not available")
            print("💡 You can only drop deployments if you have the deployment ID")
            print("   Check your CI logs for deployment IDs from failed runs")
            return None
        
        else:
            print(f"\n❌ Error: {resp.status_code}")
            print(resp.text)
            return None
    
    except Exception as e:
        print(f"\n❌ Exception: {e}")
        return None

def get_deployment_status(deployment_id):
    """Get status of a specific deployment"""
    headers = get_auth_header()
    url = f"{BASE_URL}/status?id={deployment_id}"
    
    try:
        resp = requests.post(url, headers=headers, json={"deploymentId": deployment_id})
        
        if resp.status_code == 200:
            return resp.json()
        else:
            print(f"❌ Error getting status: {resp.status_code}")
            return None
    
    except Exception as e:
        print(f"❌ Exception: {e}")
        return None

def drop_deployment(deployment_id):
    """Drop (delete) a deployment"""
    headers = get_auth_header()
    url = f"{BASE_URL}/deployment/{deployment_id}"
    
    print(f"\n🗑️  Dropping deployment: {deployment_id}")
    print(f"🔗 [DELETE] {url}")
    
    try:
        resp = requests.delete(url, headers=headers)
        
        if resp.status_code in [200, 204]:
            print("✅ Dropped successfully")
            return True
        else:
            print(f"❌ Drop failed: {resp.status_code}")
            print(resp.text)
            return False
    
    except Exception as e:
        print(f"❌ Exception: {e}")
        return False

def clean_failed():
    """Clean up all FAILED deployments"""
    deployments = list_deployments()
    
    if not deployments:
        return
    
    failed = [d for d in deployments if d.get('deploymentState') == 'FAILED']
    
    if not failed:
        print("\n✅ No FAILED deployments to clean")
        return
    
    print(f"\n🧹 Found {len(failed)} FAILED deployment(s)")
    
    for dep in failed:
        dep_id = dep.get('deploymentId')
        name = dep.get('deploymentName')
        print(f"\n  • {name} ({dep_id[:8]}...)")
        drop_deployment(dep_id)

def clean_all():
    """Clean up all non-PUBLISHED deployments"""
    deployments = list_deployments()
    
    if not deployments:
        return
    
    to_clean = [d for d in deployments if d.get('deploymentState') != 'PUBLISHED']
    
    if not to_clean:
        print("\n✅ No deployments to clean")
        return
    
    print(f"\n🧹 Found {len(to_clean)} deployment(s) to clean")
    print("\n⚠️  WARNING: This will drop ALL non-published deployments including:")
    print("   - FAILED")
    print("   - VALIDATING") 
    print("   - PUBLISHING")
    
    confirm = input("\nType 'yes' to confirm: ")
    if confirm.lower() != 'yes':
        print("❌ Cancelled")
        return
    
    for dep in to_clean:
        dep_id = dep.get('deploymentId')
        name = dep.get('deploymentName')
        state = dep.get('deploymentState')
        print(f"\n  • {name} ({state}) - {dep_id[:8]}...")
        drop_deployment(dep_id)

def main():
    parser = argparse.ArgumentParser(
        description='Maven Central deployment cleanup utility',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    parser.add_argument('--list', action='store_true',
                       help='List all deployments')
    parser.add_argument('--drop', metavar='ID',
                       help='Drop a specific deployment by ID')
    parser.add_argument('--status', metavar='ID',
                       help='Get status of a specific deployment')
    parser.add_argument('--clean-failed', action='store_true',
                       help='Clean up all FAILED deployments')
    parser.add_argument('--clean-all', action='store_true',
                       help='Clean up all non-PUBLISHED deployments (interactive)')
    
    args = parser.parse_args()
    
    if args.list:
        list_deployments()
    
    elif args.drop:
        drop_deployment(args.drop)
    
    elif args.status:
        status = get_deployment_status(args.status)
        if status:
            print("\n📊 Deployment Status:")
            print(json.dumps(status, indent=2))
    
    elif args.clean_failed:
        clean_failed()
    
    elif args.clean_all:
        clean_all()
    
    else:
        parser.print_help()

if __name__ == "__main__":
    main()
