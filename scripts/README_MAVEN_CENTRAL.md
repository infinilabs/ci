# Maven Central Deployment Management

## Scripts

### `publish_central.py`
Publishes artifacts to Maven Central.

**Usage:**
```bash
export OSSRH_USERNAME="your-username"
export OSSRH_PASSWORD="your-token"
export ZIP_FILE_PATH="/path/to/bundle.zip"
export DEBUG=true  # optional

python3 scripts/publish_central.py
```

### `cleanup_central.py`
Manages and cleans up Maven Central deployments.

**List all deployments:**
```bash
export OSSRH_USERNAME="your-username"
export OSSRH_PASSWORD="your-token"

python3 scripts/cleanup_central.py --list
```

**Check status of a specific deployment:**
```bash
python3 scripts/cleanup_central.py --status DEPLOYMENT_ID
```

**Drop a specific failed deployment:**
```bash
python3 scripts/cleanup_central.py --drop DEPLOYMENT_ID
```

**Clean up all FAILED deployments:**
```bash
python3 scripts/cleanup_central.py --clean-failed
```

**Clean up ALL non-published deployments (interactive):**
```bash
python3 scripts/cleanup_central.py --clean-all
```

## Common Scenarios

### After a failed CI run

1. Check CI logs for the deployment ID
2. Verify it failed:
   ```bash
   python3 scripts/cleanup_central.py --status DEPLOYMENT_ID
   ```
3. Drop it:
   ```bash
   python3 scripts/cleanup_central.py --drop DEPLOYMENT_ID
   ```

### Clean up all failed deployments at once

```bash
python3 scripts/cleanup_central.py --clean-failed
```

### Before a new release

List all deployments to ensure nothing is stuck:
```bash
python3 scripts/cleanup_central.py --list
```

## Deployment States

- **VALIDATING** - Being validated (signatures, checksums, POM)
- **PUBLISHING** - Validation passed, syncing to Maven Central
- **PUBLISHED** - Successfully published
- **FAILED** - Validation or publishing failed

## Notes

- Maven Central may not have a list endpoint. In that case, you need the deployment ID from CI logs.
- Deployment IDs are printed in the CI output when publishing.
- `PUBLISHING` state can take 10-30 minutes to complete.
- Only `FAILED` deployments need cleanup; `PUBLISHED` ones are final.
