#!/usr/bin/env python3

import os
import sys
import shutil
import subprocess
import time
import socket
import signal
import base64
from pathlib import Path

# ================= CONFIGURATION =================
LOG_IDENTIFIER = 'COCO_TEST'

# Resolve absolute path to the project root
PROJECT_ROOT = Path(os.getcwd()).resolve()

# Critical Paths
# Note: Ensure this filename matches your actual file (import_data_raw.py vs import_es_raw.py)
TESTS_DIR = PROJECT_ROOT / "tests"
COCO_BIN = PROJECT_ROOT / "bin" / "coco"
SERVER_LOG_FILE = PROJECT_ROOT / "coco_server.log"
PID_FILE = PROJECT_ROOT / "integration_test_coco.pid"
SNAPSHOT_SCRIPT = TESTS_DIR / "snapshot" / "import_data_raw.py"

# Easysearch Server
# Defaults to https://localhost:9200 if not set in ENV
ES_ENDPOINT = os.getenv("ES_ENDPOINT", "https://localhost:9200") 
ES_USERNAME = os.getenv("ES_USERNAME", "admin")
ES_PASSWORD = os.getenv("ES_PASSWORD", "changeme")

# Ports to check
PORT_HTTP = 9000
PORT_RPC = 2900

# Max wait time for start/stop (3 minutes)
SERVER_WAIT_TIMEOUT = 180 

# ================= HELPER FUNCTIONS =================

def log(msg, level="INFO"):
    """Print a formatted log message."""
    print(f"[{LOG_IDENTIFIER}_{level}]: {msg}", flush=True)

def run_cmd(command, check=True):
    """Wrapper to run shell commands using subprocess."""
    log(f"Executing: {command}", level="DEBUG")
    try:
        result = subprocess.run(
            command, 
            shell=True, 
            check=check, 
            text=True
        )
        return result
    except subprocess.CalledProcessError as e:
        log(f"Command failed: [{command}]", level="ERROR")
        log(f"Exit code: {e.returncode}", level="ERROR")
        
        # Dump Easysearch logs if in CI
        if os.getenv("GITHUB_ACTIONS") == "true":
            # Adjusted path based on typical CI setups
            es_log = Path.home() / "easysearch" / "logs" / "easysearch.log"
            if es_log.exists():
                log("--- Dumping Easysearch logs ---", level="DEBUG")
                print(es_log.read_text(errors='replace'))
                log("--- End of logs ---", level="DEBUG")
        
        # Dump Coco Server logs if available
        if SERVER_LOG_FILE.exists():
            log("--- Dumping Coco Server logs ---", level="DEBUG")
            print(SERVER_LOG_FILE.read_text(errors='replace'))
            log("--- End of logs ---", level="DEBUG")

        raise e

def resolve_loadgen():
    """Locate the 'loadgen' binary."""
    if shutil.which("loadgen"):
        return "loadgen"
    
    local_bin = PROJECT_ROOT / "bin" / "loadgen"
    if local_bin.exists():
        return str(local_bin.absolute())

    log("Error: 'loadgen' binary not found in PATH or ./bin/", level="FATAL")
    sys.exit(1)

def check_project_root():
    """Verify execution context."""
    files_to_check = ["README.md", "coco.yml", "tests"]
    missing = [f for f in files_to_check if not (PROJECT_ROOT / f).exists()]
    
    if missing:
        log(f"Error: Not in project root. Missing files: {missing}", level="FATAL")
        sys.exit(1)

# ================= SERVER MANAGEMENT =================

def check_port(port):
    """Return True if port is open (accepting connections)."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(1) # Short timeout for individual check
        return s.connect_ex(('127.0.0.1', port)) == 0

def wait_for_ports(ports, target_state='open', timeout=30):
    """
    Wait for ports to match the target state ('open' or 'closed').
    """
    start_time = time.time()
    while time.time() - start_time < timeout:
        all_match = True
        for port in ports:
            is_open = check_port(port)
            if target_state == 'open' and not is_open:
                all_match = False
            elif target_state == 'closed' and is_open:
                all_match = False
        
        if all_match:
            return True
        
        time.sleep(1)
        
    log(f"Timeout ({timeout}s) waiting for ports {ports} to be {target_state}", level="WARN")
    return False

def start_coco_server():
    """Start the coco binary in the background."""
    if COCO_BIN.exists():
        log(f"Coco binary found at {COCO_BIN}", level="DEBUG")
    else:
        log(f"Error: Coco binary not found at {COCO_BIN}", level="FATAL")
        sys.exit(1)

    log("Starting Coco Server...", level="STEP")
    
    # Open log file for appending (overwrite for new test run)
    with open(SERVER_LOG_FILE, "w") as log_f:
        # Start process
        proc = subprocess.Popen(
            [str(COCO_BIN)],
            stdout=log_f,
            stderr=subprocess.STDOUT,
            cwd=PROJECT_ROOT,
            start_new_session=True # Detach from parent
        )

    # Save PID
    PID_FILE.write_text(str(proc.pid))
    
    # Wait for ports to open
    if wait_for_ports([PORT_HTTP, PORT_RPC], 'open', timeout=SERVER_WAIT_TIMEOUT):
        log("Coco Server is UP.", level="SUCCESS")
    else:
        log("Failed to start Coco Server (Timeout).", level="ERROR")
        if SERVER_LOG_FILE.exists():
            print(SERVER_LOG_FILE.read_text())
        stop_coco_server() # Attempt cleanup
        sys.exit(1)

def stop_coco_server():
    """Stop the coco server using the PID file."""
    if not PID_FILE.exists():
        return

    try:
        pid_str = PID_FILE.read_text().strip()
        if not pid_str:
            return
            
        pid = int(pid_str)
        log(f"Stopping Coco Server (PID: {pid})...", level="STEP")
        
        # Send SIGTERM
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            log("Process already gone.", level="DEBUG")
        
        # Wait for ports to close
        if not wait_for_ports([PORT_HTTP, PORT_RPC], 'closed', timeout=SERVER_WAIT_TIMEOUT):
            log("Warning: Server ports did not close in time. Sending SIGKILL...", level="WARN")
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        
    except ValueError:
        log("Invalid PID file content.", level="WARN")
    except Exception as e:
        log(f"Error stopping server: {e}", level="ERROR")
    finally:
        # Clean up PID file
        if PID_FILE.exists():
            PID_FILE.unlink()

# ================= CORE LOGIC =================

def run_single_dsl_test(dsl_file, loadgen_bin):
    """
    Execute lifecycle: Stop -> Restore -> Start -> Run -> Stop
    """
    dsl_path = str(Path(dsl_file).absolute())
    log(f"Lifecycle START for: {dsl_file.name}", level="HEADER")

    try:
        # 1. Cleanup Environment
        log("1. Cleaning up previous environment...", level="STEP")
        stop_coco_server()

        # 2. Restore Data
        log("2. Restoring Easysearch data...", level="STEP")
        run_cmd(f"python3 {SNAPSHOT_SCRIPT}", check=True)

        # 3. Check if restore was successful
        log("3. Verifying data restore...", level="STEP")
        
        # Calculate Basic Auth in Python
        user_pass = f"{ES_USERNAME}:{ES_PASSWORD}"
        b64_auth = base64.b64encode(user_pass.encode('utf-8')).decode('utf-8')

        # Wait a few seconds for ES to stabilize
        time.sleep(2)

        # Construct curl command
        # -k: Insecure (ignore self-signed certs)
        # -s: Silent
        # ES_ENDPOINT usually contains https://, so don't double append
        verify_cmd = f"curl -k -s -X GET -H 'Authorization: Basic {b64_auth}' {ES_ENDPOINT}/_cat/indices?v"
        
        run_cmd(verify_cmd, check=True)

        # 4. Start Service
        log("4. Starting Coco Server...", level="STEP")
        start_coco_server()

        # 5. Run Test (Loadgen)
        log("5. Running Loadgen test...", level="STEP")
        config_path = TESTS_DIR / "loadgen.yml"
        cmd = f"{loadgen_bin} -config {config_path} -run {dsl_path} -debug"
        run_cmd(cmd, check=True)

        log(f"Test PASSED: {dsl_file.name}", level="SUCCESS")

    except subprocess.CalledProcessError:
        log(f"Test FAILED: {dsl_file.name}", level="ERROR")
        sys.exit(1)
    except Exception as e:
        log(f"Unexpected Exception: {e}", level="ERROR")
        sys.exit(1)
    finally:
        # 6. Final Cleanup
        log("6. Final cleanup...", level="STEP")
        stop_coco_server()

def main():
    check_project_root()
    loadgen_bin = resolve_loadgen()
    log(f"Using loadgen binary: {loadgen_bin}", level="INFO")

    dsl_files = sorted(list(TESTS_DIR.glob("**/*.dsl")))
    
    if not dsl_files:
        log("No .dsl files found under tests/.", level="WARN")
        return

    log(f"Found {len(dsl_files)} DSL scenarios to run.", level="INFO")

    for i, dsl_file in enumerate(dsl_files, start=1):
        print("\n" + "="*80)
        log(f"SCENARIO [{i}/{len(dsl_files)}]: {dsl_file.name}", level="START")
        print("="*80 + "\n")
        
        run_single_dsl_test(dsl_file, loadgen_bin)

    print("\n" + "="*80)
    log(f"All {len(dsl_files)} tests passed successfully!", level="SUCCESS")
    print("="*80 + "\n")

if __name__ == "__main__":
    main()