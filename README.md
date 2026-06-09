# Code Workspace Viewer

A lightweight workspace viewer that builds and renders a local-style IDE file tree directly from any public or private GitHub repository using the GitHub Git Trees API. 

## Project Structure

├── README.md
├── macOS-App/
│   ├── WorkspaceView.swift      # Main SplitView Layout
│   ├── GitHubClient.swift       # API Tree Parser
│   └── CodeContentView.swift    # Raw File Content Fetcher
└── CLI-Python/
└── workspace_viewer.py      # Terminal Tree Viewer
