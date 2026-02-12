# Branch Strategy for tongsuo-java-sdk

This document explains the branch strategy used between the `infinilabs/tongsuo-java-sdk` repository and Maven Central publishing in the CI repository.

## Branches Overview

```
tongsuo-java-sdk repository:
├── master          # Main development branch
├── dev_publish     # Maven Central publishing branch (used by CI)
└── multiplatform   # Reserved for PRs to official Tongsuo-Project/tongsuo-java-sdk
```

## Branch Purposes

### `master` Branch
- **Purpose**: Main development branch
- **Contains**: All general development work
- **Updates**: Regular commits, feature development
- **Used by**: Developers, general CI/CD

### `dev_publish` Branch  
- **Purpose**: Dedicated branch for Maven Central publishing
- **Contains**: `master` + Maven-specific optimizations
- **Updates**: Periodically merged from `master`
- **Used by**: CI publish-tongsuo-maven.yml workflow

**Why separate?**
- Keeps Maven-specific changes isolated
- Allows CI-specific optimizations without polluting master
- Can have different release cadence than master
- Easier to maintain and troubleshoot publishing issues

### `multiplatform` Branch
- **Purpose**: Reserved for syncing PRs to official Tongsuo repository
- **Contains**: Clean changes suitable for upstream contribution
- **Updates**: Only for upstream-ready features
- **Used by**: Creating PRs to `Tongsuo-Project/tongsuo-java-sdk`

**Why reserved?**
- Keeps clean history for upstream contributions
- No CI-specific or INFINI-specific changes
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

### Updating dev_publish
```bash
# Periodically merge master into dev_publish
git checkout dev_publish
git pull
git merge master -m "Merge master into dev_publish"
git push origin dev_publish
```

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
    default: 'dev_publish'
```

This means:
- ✅ Manual triggers default to `dev_publish`
- ✅ Can override to test other branches
- ✅ Scheduled builds use `dev_publish`

## Key Differences: dev_publish vs master

| Aspect | master | dev_publish |
|--------|--------|-------------|
| **Javadoc** | `failOnError = false` | Same (merged from master) |
| **Publishing Config** | SDK's default | Overridden by CI |
| **Release Workflow** | GitHub releases | Maven Central |
| **Update Frequency** | Continuous | As needed for releases |
| **Stability** | Development | Release-ready |

## Future Considerations

### Option 1: Merge Back to Master (Recommended)
After upstream sync is complete and `multiplatform` branch is deleted:
```bash
# dev_publish becomes unnecessary
# All changes can go directly to master
# CI can use master directly
```

### Option 2: Keep Separate (Current)
If we continue having CI-specific needs:
- Keep `dev_publish` for Maven Central
- Keep `master` for development
- Merge `master` → `dev_publish` before each release

## Migration Notes

**Previous Setup:**
- Used `multiplatform` branch for CI builds
- Mixed upstream-sync and CI-specific changes
- Confusing when trying to create clean upstream PRs

**New Setup:**
- `dev_publish` for CI builds
- `multiplatform` reserved for upstream
- Clear separation of purposes

## Related Files

- `ci/.github/workflows/publish-tongsuo-maven.yml` - Uses dev_publish
- `ci/products/tongsuo/publishing-maven-central.gradle` - Maven publishing config
- `ci/products/tongsuo/README.md` - Publishing documentation
