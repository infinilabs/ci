# Branch Strategy for tongsuo-java-sdk

This document explains the branch strategy used between the `infinilabs/tongsuo-java-sdk` repository and Maven Central publishing in the CI repository.

## Branches Overview

```
tongsuo-java-sdk repository:
├── master          # Main development & Maven publishing branch
└── multiplatform   # Reserved for PRs to official Tongsuo-Project/tongsuo-java-sdk
```

## Branch Purposes

### `master` Branch
- **Purpose**: Main development and Maven Central publishing
- **Contains**: All development work + publishing optimizations
- **Updates**: Regular commits, feature development, releases
- **Used by**: 
  - Developers for development
  - CI for Maven Central publishing
  - General CI/CD workflows

**Simplicity**: One branch for both development and publishing keeps things simple.

### `multiplatform` Branch
- **Purpose**: Reserved for syncing PRs to official Tongsuo repository
- **Contains**: Clean changes suitable for upstream contribution
- **Updates**: Only for upstream-ready features
- **Used by**: Creating PRs to `Tongsuo-Project/tongsuo-java-sdk`

**Why reserved?**
- Keeps clean history for upstream contributions
- No INFINI-specific changes
- Maintains good relationship with upstream project
- Can be deleted after successful upstream merge

## Workflow

### Regular Development
```bash
# Work on master
git checkout master
git pull
# ... make changes ...
git commit -m "Feature: ..."
git push origin master
```

### Maven Publishing
CI automatically uses `master` branch for publishing builds.

### Creating Upstream PR
```bash
# Create clean branch for upstream
git checkout master
git checkout -b feature-for-upstream
# ... make clean changes ...
git push origin feature-for-upstream
# Create PR to Tongsuo-Project/tongsuo-java-sdk
```

## CI Configuration

The CI workflow `publish-tongsuo-maven.yml` uses:
```yaml
inputs:
  BRANCH:
    description: 'tongsuo-java-sdk branch to build from'
    default: 'master'
```

This means:
- ✅ Manual triggers default to `master`
- ✅ Can override to test other branches
- ✅ Scheduled builds use `master`

## Key Features in master

| Feature | Status | Purpose |
|---------|--------|---------|
| **Javadoc failOnError** | ✅ Disabled | Allows publishing with javadoc warnings |
| **Multi-platform support** | ✅ Enabled | x86_64, aarch64, macOS, Windows |
| **GLIBC compatibility** | ✅ 2.27 | Via Ubuntu 18.04 Docker |
| **Publishing config** | 🔄 Overridden by CI | CI uses custom publishing-maven-central.gradle |

## Removed: dev_publish Branch

**Previous approach**: Had separate `dev_publish` branch for Maven publishing.

**Why removed**: 
- ❌ Unnecessary complexity
- ❌ Need to sync between master and dev_publish
- ❌ Confusing which branch to use
- ✅ master already has all necessary fixes
- ✅ Simpler to maintain one branch

## Related Files

- `ci/.github/workflows/publish-tongsuo-maven.yml` - Uses master branch
- `ci/products/tongsuo/publishing-maven-central.gradle` - Maven publishing config
- `ci/products/tongsuo/README.md` - Publishing documentation

