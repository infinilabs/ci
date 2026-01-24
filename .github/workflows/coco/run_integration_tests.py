#!/usr/bin/env python3

import os
import sys
import shutil
import subprocess
import time
import socket
import signal
from pathlib import Path

# ================= CONFIGURATION =================
LOG_IDENTIFIER = 'COCO_TEST_INFO'

# Resolve absolute path to the project root
PROJECT_ROOT = Path(os.getcwd()).resolve()

# Critical Paths
SNAPSHOT_SCRIPT = PROJECT_ROOT / "snapshot" / "import_es_raw.py"
TESTS_DIR = PROJECT_ROOT / "tests"
COCO_BIN = PROJECT_ROOT / "bin" / "coco"
PID_FILE = PROJECT_ROOT / "integration_test_coco.pid"
SERVER_LOG_FILE = PROJECT_ROOT / "coco_server.log"

# Ports to check
PORT_HTTP = 9000
PORT_RPC = 2900

# Max wait time for start/stop (3 minutes)
SERVER_WAIT_TIMEOUT = 180 

# ================= HELPER FUNCTIONS =================

def log(msg):
    """Print a formatted log message."""
    print(f"{LOG_IDENTIFIER}: {msg}", flush=True)

def run_cmd(command, check=True):
    """Wrapper to run shell commands using subprocess."""
    try:
        result = subprocess.run(
            command, 
            shell=True, 
            check=check, 
            text=True
        )
        return result
    except subprocess.CalledProcessError as e:
        log(f"Command failed: [{command}]")
        log(f"Exit code: {e.returncode}")
        
        # Dump Easysearch logs if in CI
        if os.getenv("GITHUB_ACTIONS") == "true":
            es_log = Path.home() / "es_install_dir" / "easysearch.log"
            if es_log.exists():
                log("--- Dumping Easysearch logs ---")
                print(es_log.read_text(errors='replace'))
                log("--- End of logs ---")
        
        # Dump Coco Server logs if available
        if SERVER_LOG_FILE.exists():
            log("--- Dumping Coco Server logs ---")
            print(SERVER_LOG_FILE.read_text(errors='replace'))
            log("--- End of logs ---")

        raise e

def resolve_loadgen():
    """Locate the 'loadgen' binary."""
    if shutil.which("loadgen"):
        return "loadgen"
    
    local_bin = PROJECT_ROOT / "bin" / "loadgen"
    if local_bin.exists():
        return str(local_bin.absolute())

    log("Error: 'loadgen' binary not found in PATH or ./bin/")
    sys.exit(1)

def check_project_root():
    """Verify execution context."""
    files_to_check = ["README.md", "coco.yml", "tests"]
    missing = [f for f in files_to_check if not (PROJECT_ROOT / f).exists()]
    
    if missing:
        log(f"Error: Not in project root. Missing files: {missing}")
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
        
    log(f"Timeout ({timeout}s) waiting for ports {ports} to be {target_state}")
    return False

def start_coco_server():
    """Start the coco binary in the background."""
    if not COCO_BIN.exists():
        log(f"Error: Coco binary not found at {COCO_BIN}")
        sys.exit(1)

    log("Starting Coco Server...")
    
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
    
    # Wait for ports to open (Up to 3 minutes)
    if wait_for_ports([PORT_HTTP, PORT_RPC], 'open', timeout=SERVER_WAIT_TIMEOUT):
        log("Coco Server is UP.")
    else:
        log("Failed to start Coco Server (Timeout).")
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
        log(f"Stopping Coco Server (PID: {pid})...")
        
        # Send SIGTERM
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            log("Process already gone.")
        
        # Wait for ports to close (Up to 3 minutes)
        if not wait_for_ports([PORT_HTTP, PORT_RPC], 'closed', timeout=SERVER_WAIT_TIMEOUT):
            log("Warning: Server ports did not close in time. Sending SIGKILL...")
            try:
                os.kill(pid, signal.SIGKILL)
            except OSError:
                pass
        
    except ValueError:
        log("Invalid PID file content.")
    except Exception as e:
        log(f"Error stopping server: {e}")
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
    log(f"Starting test lifecycle for: {dsl_file}")

    try:
        # 1. Cleanup Environment
        stop_coco_server()

        # 2. Restore Data
        run_cmd(f"python3 {SNAPSHOT_SCRIPT}", check=True)

        # 3. Start Service
        start_coco_server()

        # 4. Run Test (Loadgen)
        config_path = TESTS_DIR / "loadgen.yml"
        cmd = f"{loadgen_bin} -config {config_path} -run {dsl_path} -debug"
        run_cmd(cmd, check=True)

        log(f"Test PASSED: {dsl_file}")

    except subprocess.CalledProcessError:
        log(f"Test FAILED: {dsl_file}")
        sys.exit(1)
    finally:
        # 5. Final Cleanup
        stop_coco_server()

def main():
    check_project_root()
    loadgen_bin = resolve_loadgen()
    log(f"Using loadgen binary: {loadgen_bin}")

    dsl_files = sorted(list(TESTS_DIR.glob("**/*.dsl")))
    
    if not dsl_files:
        log("No .dsl files found under tests/.")
        return

    log(f"Found {len(dsl_files)} DSL scenarios to run.")

    for i, dsl_file in enumerate(dsl_files, start=1):
        print("\n" + "="*60)
        log(f"Running scenario [{i}/{len(dsl_files)}]: {dsl_file.name}")
        print("="*60 + "\n")
        run_single_dsl_test(dsl_file, loadgen_bin)

    print("\n" + "="*60)
    log(f"All {len(dsl_files)} tests passed successfully!")
    print("="*60 + "\n")

if __name__ == "__main__":
    main()