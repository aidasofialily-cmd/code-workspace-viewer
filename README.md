# GitHub Universal Code Workspace Viewer

A terminal-based workspace viewer that scans a GitHub repository recursively, builds an on-the-fly local layout tree, and reads/filters source files for Swift, Python, and C++.

## 🚀 Features
- **Zero Xcode dependency:** Runs directly inside your standard macOS/Linux Terminal.
- **Language Filtering:** Groups and lists files by extensions (`.swift`, `.py`, `.cpp`, `.hpp`, `.h`).
- **Tree-view Visualization:** Pretty-prints the remote repository structure right in the console.

## 🛠️ Prerequisites
Make sure you have Python 3.x installed. You will also need the `requests` library to handle GitHub API calls.

```bash
pip install requests
