# Maven Central Publishing Configuration

This directory contains custom Gradle publishing configuration for publishing Tongsuo Java SDK to Maven Central.

## Purpose

The CI repository and the SDK repository have different publishing requirements:

- **SDK Repository** (`tongsuo-java-sdk`): 
  - Publishes to GitHub Releases
  - Uses groupId: `net.tongsuo`
  - Creates uber JARs with all platforms
  - Focused on easy distribution for end users

- **CI Repository** (this):
  - Publishes to Maven Central
  - Uses groupId: `com.infinilabs`
  - Creates platform-specific artifacts with classifiers
  - Focused on Maven dependency management

## Files

### `publishing-maven-central.gradle`

This file replaces the SDK's default `gradle/publishing.gradle` during CI builds. It:

1. **Sets custom groupId**: `com.infinilabs` instead of `net.tongsuo`
2. **Adds platform classifiers**: 
   - `linux-x86_64`, `linux-aarch_64`
   - `osx-x86_64`, `osx-aarch_64`
   - `windows-x86_64`
3. **Publishes three artifacts per platform**:
   - Main JAR: `tongsuo-openjdk-1.1.0-linux-x86_64.jar`
   - Sources: `tongsuo-openjdk-1.1.0-linux-x86_64-sources.jar`
   - Javadoc: `tongsuo-openjdk-1.1.0-linux-x86_64-javadoc.jar`
4. **Configures signing**: Uses environment variables for GPG signing
5. **Sets custom POM metadata**: INFINI Labs as developer/organization

## How It Works

During the CI build:

1. The workflow copies `publishing-maven-central.gradle` to `openjdk/build.gradle.custom`
2. Uses `sed` to replace the line in `openjdk/build.gradle`:
   ```gradle
   // Before:
   apply from: "$rootDir/gradle/publishing.gradle"
   
   // After:
   apply from: "build.gradle.custom"
   ```
3. Runs Gradle with normal commands (no init scripts needed)

## Benefits

✅ **Clean separation**: SDK and CI use completely different publishing configs  
✅ **No conflicts**: Doesn't interfere with SDK's default publishing  
✅ **Easy maintenance**: Single file to update for all CI publishing changes  
✅ **Standard Gradle**: Uses normal plugin mechanisms, not init scripts  
✅ **Version control**: Publishing config is tracked in CI repo, not SDK repo  

## Platform Classifiers

The configuration automatically detects the platform and applies the correct classifier:

| Platform | Classifier |
|----------|------------|
| Linux x86_64 | `linux-x86_64` |
| Linux aarch64 | `linux-aarch_64` |
| macOS x86_64 | `osx-x86_64` |
| macOS ARM64 | `osx-aarch_64` |
| Windows x86_64 | `windows-x86_64` |

## Environment Variables

### Required for Publishing

- `SIGNING_KEY`: GPG private key (ASCII-armored)
- `SIGNING_PASSWORD`: GPG key passphrase

### Build Properties

- `-Pversion`: Version to publish (e.g., `1.1.0`)
- `-PtongsuoHome`: Path to Tongsuo installation
- `-PcheckErrorQueue`: Enable error queue checking

## Example Usage

```bash
# Copy custom publishing config
cp publishing-maven-central.gradle /path/to/tongsuo-java-sdk/openjdk/build.gradle.custom

# Modify openjdk/build.gradle to use it
cd /path/to/tongsuo-java-sdk
sed -i 's|apply from: "$rootDir/gradle/publishing.gradle"|apply from: "build.gradle.custom"|' openjdk/build.gradle

# Build and publish
./gradlew -Pversion=1.1.0 \
          -PtongsuoHome=/opt/tongsuo \
          -PcheckErrorQueue \
          :tongsuo-openjdk:publishToMavenLocal
```

## Maven Central Deployment

After all platforms build:

1. Artifacts are collected from Maven Local repositories
2. Bundled into a single directory structure
3. Uploaded to Maven Central staging repository
4. Released after validation

See `../.github/workflows/publish-tongsuo-maven.yml` for the complete workflow.
