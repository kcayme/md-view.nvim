# Vimdoc Automation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a GitHub Actions workflow that generates `doc/md-view.nvim.txt` from the project's Markdown docs on every version tag push and commits it back to `main`.

**Architecture:** On `v*.*.*` tag push, the workflow checks out `main`, concatenates README + ARCHITECTURE + recipes into a temp file inside the workspace (demoting secondary H1s to H2), runs `kdheepak/panvimdoc` to produce `doc/md-view.nvim.txt`, then auto-commits the result back to `main` via `stefanzweifel/git-auto-commit-action`.

**Tech Stack:** GitHub Actions, `kdheepak/panvimdoc@v4`, `stefanzweifel/git-auto-commit-action@v7`, `actions/checkout@v4`

---

## Chunk 1: GitHub Actions Workflow

### Task 1: Create the vimdoc workflow file

**Files:**
- Create: `.github/workflows/vimdoc.yml`

- [ ] **Step 1: Create `.github/workflows/` directory and workflow file**

```bash
mkdir -p .github/workflows
```

Create `.github/workflows/vimdoc.yml` with the following content:

```yaml
name: Generate Vimdoc

on:
  push:
    tags:
      - "v*.*.*"

jobs:
  vimdoc:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    steps:
      - uses: actions/checkout@v4
        with:
          ref: main

      - name: Concatenate documentation sources
        run: |
          set -euo pipefail
          test -f README.md
          test -f docs/ARCHITECTURE.md
          test -f docs/recipes/picker-integration.md

          cat README.md > .doc-source.md
          printf "\n\n" >> .doc-source.md
          sed 's/^#\([^#]\)/##\1/' docs/ARCHITECTURE.md >> .doc-source.md
          printf "\n\n" >> .doc-source.md
          sed 's/^#\([^#]\)/##\1/' docs/recipes/picker-integration.md >> .doc-source.md

      - uses: kdheepak/panvimdoc@v4
        with:
          vimdoc: md-view.nvim
          pandoc: .doc-source.md

      - uses: stefanzweifel/git-auto-commit-action@v7
        with:
          commit_message: "docs: generate vimdoc [skip ci]"
          file_pattern: doc/md-view.nvim.txt
          branch: main
```

- [ ] **Step 2: Verify YAML syntax is valid**

```bash
python3 -c "import yaml, sys; yaml.safe_load(open('.github/workflows/vimdoc.yml'))" && echo "YAML OK"
```

Expected: `YAML OK`

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/vimdoc.yml
git commit -m "feat: add GitHub Actions workflow for vimdoc generation"
```
