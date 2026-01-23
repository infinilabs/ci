#!/usr/bin/env python3

import os
import sys
import shutil
import subprocess
from pathlib import Path

# ================= CONFIGURATION =================
LOG_IDENTIFIER = 'COCO_TEST_INFO'

# Resolve absolute path to the project root (assumes script is run from root)
PROJECT_ROOT = Path(os.getcwd()).resolve()

# Path to the snapshot restoration script
# Note: Ensure the filename matches your actual script name
SNAPSHOT_SCRIPT = PROJECT_ROOT / "snapshot" / "import_es_raw.py"

# Path to the tests directory
TESTS_DIR = PROJECT_ROOT / "tests"

# ================= HELPER FUNCTIONS =================

def log(msg):
    """
    Print a formatted log message.
    """
    print(f"{LOG_IDENTIFIER}: {msg}", flush=True)

def run_cmd(command, check=True, cwd=None):
    """
    Wrapper to run shell commands using subprocess.
    """
    try:
        # shell=True allows using compound commands (e.g., bash scripts)
        result = subprocess.run(
            command, 
            shell=True, 
            check=check, 
            cwd=cwd,
            text=True
        )
        return result
    except subprocess.CalledProcessError as e:
        log(f"Command failed: [{command}]")
        log(f"Exit code: {e.returncode}")
        
        # CI Debugging: Dump Easysearch logs if running in GitHub Actions
        if os.getenv("GITHUB_ACTIONS") == "true":
            es_log = Path.home() / "es_install_dir" / "easysearch.log"
            if es_log.exists():
                log("--- Dumping Easysearch logs ---")
                print(es_log.read_text(errors='replace'))
                log("--- End of logs ---")
        
        raise e

def resolve_loadgen():
    """
    Locate the 'loadgen' binary.
    Since you added it to GITHUB_PATH, shutil.which("loadgen") should succeed.
    """
    # 1. Check system PATH (Preferred for CI)
    if shutil.which("loadgen"):
        return "loadgen"
    
    # 2. Fallback: Check local project bin directory (For local dev convenience)
    local_bin = PROJECT_ROOT / "bin" / "loadgen"
    if local_bin.exists():
        return str(local_bin.absolute())

    log("Error: 'loadgen' binary not found in PATH or ./bin/")
    sys.exit(1)

def check_project_root():
    """
    Verify that the script is running from the project root directory.
    """
    files_to_check = [
        "README.md",
        "coco.yml",
        "tests",
        "start_coco.sh",
        "stop_coco.sh"
    ]
    
    missing = []
    for f in files_to_check:
        if not (PROJECT_ROOT / f).exists():
            missing.append(f)
    
    if missing:
        log(f"Error: Not in project root. Missing files: {missing}")
        sys.exit(1)

# ================= CORE LOGIC =================

def run_single_dsl_test(dsl_file, loadgen_bin):
    """
    Execute the full lifecycle for a single DSL test scenario.
    Lifecycle: Stop -> Restore Data -> Start -> Run Loadgen -> Stop
    """
    dsl_path = str(Path(dsl_file).absolute())
    
    log(f"Starting test lifecycle for: {dsl_file}")

    try:
        # 1. Cleanup Environment (Stop Coco)
        # check=False: It's okay if it fails (e.g., service not running yet)
        subprocess.run("bash ./stop_coco.sh", shell=True, check=False)

        # 2. Restore Data (Snapshot)
        # Use the absolute path to the python script
        run_cmd(f"python3 {SNAPSHOT_SCRIPT}", check=True)

        # 3. Start Service (Start Coco)
        run_cmd("bash ./start_coco.sh", check=True)

        # 4. Run Test (Loadgen)
        # Using absolute path for config to be safe
        config_path = TESTS_DIR / "loadgen.yml"
        
        cmd = f"{loadgen_bin} -config {config_path} -run {dsl_path} -debug"
        run_cmd(cmd, check=True)

        log(f"Test PASSED: {dsl_file}")

    except subprocess.CalledProcessError:
        log(f"Test FAILED: {dsl_file}")
        sys.exit(1) # Exit immediately on failure
    finally:
        # 5. Final Cleanup
        # Ensure the service is stopped and ports are released,
        # regardless of test success or failure.
        subprocess.run("bash ./stop_coco.sh", shell=True, check=False)

def main():
    check_project_root()
    
    # Resolve binary location
    loadgen_bin = resolve_loadgen()
    log(f"Using loadgen binary: {loadgen_bin}")

    # Discover all .dsl files under the tests directory
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