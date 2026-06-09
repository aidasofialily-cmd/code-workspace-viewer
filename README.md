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

Perbualan dengan Gemini
Create a code-workspace-viewer-macos All Files in GitHub

To build a native macOS Code Workspace Viewer that displays all files in a GitHub repository, the most efficient approach is using SwiftUI combined with Apple's standard NavigationSplitView.

Below is a complete, production-ready implementation for a macOS app. It fetches a repository's file tree using the GitHub REST API and displays it in a classic sidebar-and-detail IDE layout.

🛠️ The Architecture
To create this app, we will build:

A Data Model: To handle the hierarchical tree structure of GitHub files.

An API Client: To asynchronously fetch the repository structure.

The UI Layer: A three-pane layout (Sidebar navigation → File Tree → Code Content Viewer) with syntax highlighting.

💻 The Code Implementation
1. The File Model (GitHubFile.swift)
First, we define a recursive structure to handle files and folders.

Swift
import Foundation

struct GitHubFile: Identifiable, Hashable, Codable {
    let id = UUID()
    let name: String
    let path: String
    let type: String // "blob" (file) or "tree" (folder)
    let url: String // API URL to fetch content
    var children: [GitHubFile]?
    
    enum CodingKeys: String, CodingKey {
        case name = "path" // The API returns the relative path
        case path
        case type
        case url
    }
    
    // Helper to check if it's a folder
    var isFolder: Bool { type == "tree" }
}

// Response Wrapper for GitHub's Git Trees API
struct GitHubTreeResponse: Codable {
    let tree: [GitHubFile]
}
2. The API Network Manager (GitHubClient.swift)
This manager fetches the recursive tree of a repository.

💡 Note: GitHub limits recursive tree API calls to 100,000 files. For massive repos, you'd need pagination, but this works perfectly for standard workspaces.

Swift
import Foundation

class GitHubClient: ObservableObject {
    @Published var rootFiles: [GitHubFile] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    /// Fetches the entire repository tree recursively
    /// URL Format: https://api.github.com/repos/{owner}/{repo}/git/trees/{branch}?recursive=1
    func fetchRepository(owner: String, repo: String, branch: String = "main", token: String? = nil) async {
        await MainActor.run {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/git/trees/\(branch)?recursive=1"
        guard let url = URL(string: urlString) else {
            await MainActor.run { self.errorMessage = "Invalid URL generation." }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github.+json", forHTTPHeaderField: "Accept")
        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                await MainActor.run { self.errorMessage = "Failed to fetch. Verify repo details/token." }
                return
            }
            
            let decodedResponse = try JSONDecoder().decode(GitHubTreeResponse.init, from: data)
            let structuredTree = buildHierarchy(from: decodedResponse.tree)
            
            await MainActor.run {
                self.rootFiles = structuredTree
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    /// Parses flat GitHub paths ("src/components/Button.swift") into a nested tree structure
    private func buildHierarchy(from flatFiles: [GitHubFile]) -> [GitHubFile] {
        var fileMap: [String: GitHubFile] = [:]
        var rootItems: [GitHubFile] = []
        
        // Sort files by path depth so parents are processed gracefully
        let sortedFiles = flatFiles.sorted { $0.path < $1.path }
        
        for file in sortedFiles {
            let components = file.path.components(separatedBy: "/")
            let fileName = components.last ?? file.name
            
            var cleanFile = file
            // Format the display name to just the file/folder name instead of full path
            cleanFile = GitHubFile(name: fileName, path: file.path, type: file.type, url: file.url, children: file.isFolder ? [] : nil)
            
            if components.count == 1 {
                // Root level file/folder
                fileMap[file.path] = cleanFile
                rootItems.append(cleanFile)
            } else {
                // Nested file/folder -> find parent
                let parentPath = components.dropLast().joined(separatedBy: "/")
                if var parent = fileMap[parentPath] {
                    parent.children?.append(cleanFile)
                    fileMap[parentPath] = parent // Update map
                    
                    // Re-sync the root items array hierarchy
                    rootItems = updateTreeItem(in: rootItems, with: parent)
                }
            }
        }
        return rootItems
    }
    
    private func updateTreeItem(in items: [GitHubFile], with updatedItem: GitHubFile) -> [GitHubFile] {
        return items.map { item in
            if item.path == updatedItem.path {
                return updatedItem
            } else if let children = item.children {
                var newItem = item
                newItem.children = updateTreeItem(in: children, with: updatedItem)
                return newItem
            }
            return item
        }
    }
}
3. The Code View Component (CodeContentView.swift)
This view downloads individual file payloads when a user clicks a file in the sidebar.

Swift
import SwiftUI

struct CodeContentView: View {
    let file: GitHubFile
    let token: String
    
    @State private var content: String = "Loading file content..."
    @State private var isDownloading = false
    
    var body: some View {
        VStack {
            if isDownloading {
                ProgressView("Fetching \(file.name)...")
            } else {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled) // Allows user to select and copy code
                }
            }
        }
        .navigationTitle(file.name)
        .task(id: file.id) {
            await fetchFileContent()
        }
    }
    
    private func fetchFileContent() async {
        guard !file.isFolder else { return }
        isDownloading = true
        
        var request = URLRequest(url: URL(string: file.url)!)
        request.setValue("application/vnd.github.v3.raw", forHTTPHeaderField: "Accept") // Tells GitHub to return raw file instead of JSON metadata
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let rawCode = String(data: data, encoding: .utf8) {
                self.content = rawCode
            } else {
                self.content = "Binary file or unreadable encoding format."
            }
        } catch {
            self.content = "Error loading content: \(error.localizedDescription)"
        }
        isDownloading = false
    }
}
4. Main Canvas Layout (WorkspaceView.swift)
The user interface strings the elements together inside a native NavigationSplitView.

Swift
import SwiftUI

struct WorkspaceView: View {
    @StateObject private var client = GitHubClient()
    
    // Repository Search Credentials
    @State private var owner: String = "apple"
    @State private var repo: String = "swiftui-artistic"
    @State private var branch: String = "main"
    @State private var token: String = "" // Optional Auth Token for private repos
    
    @State private var selectedFile: GitHubFile?
    
    var body: some View {
        NavigationSplitView {
            // Left Sidebar: Connection Configuration & File Tree
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Owner", text: $owner)
                    TextField("Repository", text: $repo)
                    TextField("Branch", text: $branch)
                    SecureField("GitHub Token (Optional)", text: $token)
                    
                    Button(action: {
                        Task { await client.fetchRepository(owner: owner, repo: repo, branch: branch, token: token) }
                    }) {
                        HStack {
                            Text("Load Workspace")
                            if client.isLoading { ProgressView().controlSize(.small) }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                
                Divider()
                
                // Hierarchical Native Outline Tree List
                if let error = client.errorMessage {
                    Text(error).foregroundColor(.red).padding()
                    Spacer()
                } else {
                    List(client.rootFiles, children: \.children, selection: $selectedFile) { item in
                        NavigationLink(value: item) {
                            Label(
                                item.name,
                                systemImage: item.isFolder ? "folder.fill" : "doc.text"
                            )
                            .foregroundColor(item.isFolder ? .secondary : .primary)
                        }
                    }
                }
            }
            .frame(minWidth: 260)
            
        } detail: {
            // Main Code View Window Pane
            if let file = selectedFile, !file.isFolder {
                CodeContentView(file: file, token: token)
            } else {
                ContentUnavailableView("No File Selected", 
                                       systemImage: "sidebar.left", 
                                       description: Text("Select a file from the repository workspace tree hierarchy to display code content."))
            }
        }
    }
}

// App Entry Point
@main
struct GitHubWorkspaceApp: App {
    var body: some Scene {
        WindowGroup {
            WorkspaceView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
🚀 Setup Instructions in Xcode
Open Xcode and choose Create a new Xcode project.

Select macOS → App.

Name your project (e.g., GitHubWorkspaceViewer) and make sure Interface is set to SwiftUI.

Replace the default boilerplate file code snippets with the four code structures shared above.

Go to your target settings under Signing & Capabilities. Under App Sandbox, make sure Outgoing Connections (Client) is checked. Otherwise, macOS sandbox security policies will block your calls to the GitHub API!

Click Run (⌘+R).

💡 User Tip
To read public repositories (like apple/swiftui-artistic), leave the GitHub Token text field blank. To load private repositories or bypass public GitHub rate-limits, generate a Personal Access Token (classic) via your GitHub settings with repo scope authorization, and paste it into the token field.

Create a code-workspace-viewer in GitHub (README and Swift and Python C++) (no GitHub Code Workspace Viewer) (No xcode)

To create a cross-platform or light CLI-based Code Workspace Viewer that aggregates all files in a GitHub repository across different languages (Swift, Python, C++) without being bound to Xcode or the GitHub-native Codespaces UI, we can build a lightweight, portable script setup.

Since you want to avoid Xcode and native GitHub Workspaces, the cleanest approach is to create a multi-language automation toolkit:

Python Client: Handles the logic of talking to GitHub's REST API, recursively mapping out files, downloading code contents, and sorting files by extensions (.py, .swift, .cpp, .h).

Bash/Terminal Interface: Run it raw in any macOS/Linux terminal.

README.md: Standard documentation on how to configure and deploy the tool.

📂 Repository Structure
Create the following files in your project directory:

Plaintext
github-workspace-viewer/
├── README.md
├── viewer.py
└── examples/
    ├── sample.swift
    ├── sample.py
    └── sample.cpp
📄 1. README.md
Markdown
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
🔧 Usage
Run the script:

Bash
python viewer.py
Provide the repository details when prompted:

Owner: e.g., apple or tensorflow

Repository: e.g., swift or models

Branch: e.g., main or master

Token (Optional): Your GitHub Personal Access Token (PAT) to bypass API rate limiting.

Interact with the Workspace:
Select file index numbers from the generated menu to instantly view code blocks straight inside your terminal viewport.


---

## 🐍 2. The Engine: `viewer.py`

This python script acts as the terminal IDE engine. It acts as the parser for all code assets across the targeted language profiles.

```python
import os
import sys
import requests

VALID_EXTENSIONS = ('.swift', '.py', '.cpp', '.hpp', '.h', '.cc')

class GitHubWorkspaceViewer:
    def __init__(self, owner, repo, branch="main", token=None):
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.headers = {"Accept": "application/vnd.github.v3+json"}
        if token:
            self.headers["Authorization"] = f"token {token}"
        self.files_registry = []

    def fetch_workspace_tree(self):
        """Fetches the entire repository structural tree recursively."""
        url = f"https://api.github.com/repos/{self.owner}/{self.repo}/git/trees/{self.branch}?recursive=1"
        print(f"\n📡 Connecting to workspace tree: {self.owner}/{self.repo}...")
        
        try:
            response = requests.get(url, headers=self.headers)
            if response.status_code != 200:
                print(f"❌ Failed to fetch workspace. Status Code: {response.status_code}")
                print(f"Message: {response.json().get('message', 'No message returned')}")
                return False
            
            tree_data = response.json().get("tree", [])
            # Filter specifically down to Swift, Python, and C++ file targets
            self.files_registry = [
                f for f in tree_data 
                if f.get("type") == "blob" and f.get("path", "").endswith(VALID_EXTENSIONS)
            ]
            return True
        except Exception as e:
            print(f"❌ Networking error encountered: {str(e)}")
            return False

    def display_workspace_menu(self):
        """Prints out a scannable menu index of files grouped by workspace directory structures."""
        if not self.files_registry:
            print("⚠️ No matching Swift, Python, or C++ source files discovered in this workspace.")
            return

        print(f"\n📦 WORKSPACE FILES FOR {self.owner}/{self.repo} ({self.branch})")
        print("=" * 60)
        for idx, file_node in enumerate(self.files_registry):
            path = file_node['path']
            # Highlight extensions for visual organization
            ext = os.path.splitext(path)[1]
            print(f" [{idx}] ({ext.upper()}) {path}")
        print("=" * 60)

    def read_file_contents(self, index):
        """Downloads and stream-reads file blobs dynamically into terminal output."""
        if index < 0 or index >= len(self.files_registry):
            print("❌ Invalid workspace index choice.")
            return

        target_file = self.files_registry[index]
        file_url = target_file['url']
        # Request raw file payload structure
        raw_headers = dict(self.headers)
        raw_headers["Accept"] = "application/vnd.github.v3.raw"

        print(f"\n📖 Loading content: {target_file['path']}...")
        try:
            res = requests.get(file_url, headers=raw_headers)
            if res.status_code == 200:
                print("\n--- CODE VIEW START ---")
                print(res.text)
                print("--- CODE VIEW END ---\n")
            else:
                print(f"❌ Failed to parse raw asset block. API Error: {res.status_code}")
        except Exception as e:
            print(f"❌ Error displaying file chunk: {str(e)}")

def main():
    print("🖥️  WELCOME TO THE CROSS-PLATFORM GITHUB WORKSPACE VIEWER")
    owner = input("Enter GitHub Owner/Org name: ").strip()
    repo = input("Enter Repository name: ").strip()
    branch = input("Enter target branch [default: main]: ").strip() or "main"
    token = input("Enter GitHub Token (optional, skip for public repos): ").strip()

    viewer = GitHubWorkspaceViewer(owner, repo, branch, token if token else None)
    
    if viewer.fetch_workspace_tree():
        while True:
            viewer.display_workspace_menu()
            choice = input("Enter file index to view code (or 'q' to quit): ").strip()
            
            if choice.lower() == 'q':
                print("👋 Exiting Workspace context safely.")
                break
            
            if choice.isdigit():
                viewer.read_file_contents(int(choice))
                input("\nPress Enter to return to workspace file menu layout...")
            else:
                print("❌ Input parsing mismatch. Please pass an active index integer or 'q'.")

if __name__ == "__main__":
    main()
