# SPM Distribution

This repository provides a Swift Package Manager (SPM) distribution for integration with Xcode projects.

## Prerequisites

Before adding this package to your Xcode project, you need to configure authentication credentials.

## Configuration

### 1.Configure .netrc File

Add the following credentials to your `.netrc` file (located at `~/.netrc`):

```
machine sdk.arpalus.com
login token
password YOUR_JWT_TOKEN
```

**Note:** If the `.netrc` file doesn't exist, create it first. Ensure the file has the correct permissions:
```bash
chmod 600 ~/.netrc
```

## Installation

### Adding to Xcode

1. Open your project in Xcode
2. Navigate to **File → Add Package Dependencies...**
3. Enter the following repository URL:
   ```
   git@github.com:Arpalus-dev/spm-distribution.git
   ```
4. Follow the prompts to complete the package integration
