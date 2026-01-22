# Contributing to Employee Lifecycle Platform

## Getting Started

This repository is configured for simple, direct git workflows without mandatory build steps.

## Pushing Your Code

You can push your code directly to the repository without building:

```bash
# Add your files
git add .

# Commit your changes
git commit -m "Your commit message"

# Push to the repository
git push origin <branch-name>
```

## What Gets Ignored

The `.gitignore` file automatically excludes:
- Build artifacts and output directories
- Dependencies (node_modules, vendor, etc.)
- IDE and editor files
- Environment variables and secrets
- Temporary files and caches

## No Build Required

This repository does not require you to build your code before pushing. Simply add and commit your source code, and push it directly to GitHub.
