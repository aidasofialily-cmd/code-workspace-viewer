#!/usr/bin/env swift
import Foundation

// Struct mapping for the GitHub Git Data API format
struct GitHubFile: Codable {
    let path: String
    let type: String // "blob" (file) or "tree" (directory)
    let url: String  // API endpoint containing file contents
}

struct GitHubTreeResponse: Codable {
    let tree: [GitHubFile]
}

class CodeWorkspaceApp {
    private let validExtensions = [".swift", ".py", ".cpp", ".hpp", ".h", ".cc"]
    private var fileRegistry: [GitHubFile] = []
    
    private var headers: [String: String] = [
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "SwiftCodeWorkspaceApp"
    ]
    
    init(token: String?) {
        if let token = token, !token.isEmpty {
            self.headers["Authorization"] = "token \(token)"
        }
    }
    
    /// Recursively fetches metadata representing all files in the targeted repository.
    func loadWorkspaceTree(owner: String, repo: String, branch: String) -> Bool {
        let urlString = "https://api.github.com/repos/\(owner)/\(repo)/git/trees/\(branch)?recursive=1"
        guard let url = URL(string: urlString) else {
            print("❌ Error: Invalid workspace path parameters generated.")
            return false
        }
        
        var request = URLRequest(url: url)
        request.allHTTPHeaderFields = headers
        
        let semaphore = DispatchSemaphore(value: 0)
        var success = false
        
        print("\n📡 Connecting to workspace tree: \(owner)/\(repo)...")
        
        let task = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            defer { semaphore.signal() }
            
            if let error = error {
                print("❌ Network connection issue: \(error.localizedDescription)")
                return
            }
            
            guard let httpResponse = response as? HTTPURLResponse else { return }
            if httpResponse.statusCode != 200 {
                print("❌ GitHub API rejected request (Status Code: \(httpResponse.statusCode))")
                return
            }
            
            guard let data = data,
                  let decoded = try? JSONDecoder().decode(GitHubTreeResponse.self, from: data) else {
                print("❌ Parsing failure: Workspace JSON contains unrecognized structural payloads.")
                return
            }
            
            // Filter tree items specifically down to supported source languages
            self?.fileRegistry = decoded.tree.filter { item in
                guard item.type == "blob" else { return false }
                return self?.validExtensions.contains(where: { item.path.hasSuffix($0) }) ?? false
            }
            success = true
        }
        
        task.resume()
        semaphore.wait()
        return success
    }
    
    /// Displays an interactive indexed list of tracked multi-language code files.
    func renderWorkspaceMenu() {
        if fileRegistry.isEmpty {
            print("⚠️ Workspace scan completed: No Swift, Python, or C++ entries found.")
            return
        }
        
        print("\n📦 WORKSPACE FILES TREE")
        print(String(repeating: "=", count: 60))
        for (index, file) in fileRegistry.enumerated() {
            let fileURL = URL(fileURLWithPath: file.path)
            let ext = fileURL.pathExtension.uppercased()
            print(String(format: " [%2d] (%-5@) %@", index, ext, file.path))
        }
        print(String(repeating: "=", count: 60))
    }
    
    /// Fetches the raw text content of a targeted repository node.
    func streamCodeContent(at index: Int) {
        guard index >= 0 && index < fileRegistry.count else {
            print("❌ Index out of range.")
            return
        }
        
        let file = fileRegistry[index]
        guard let url = URL(string: file.url) else { return }
        
        var request = URLRequest(url: url)
        var rawHeaders = headers
        // Re-route the accept type payload to request raw code formatting instead of JSON
        rawHeaders["Accept"] = "application/vnd.github.v3.raw"
        request.allHTTPHeaderFields = rawHeaders
        
        let semaphore = DispatchSemaphore(value: 0)
        print("\n📖 Streaming plain text layout: \(file.path)...")
        
        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
            defer { semaphore.signal() }
            if let data = data, let textOutput = String(data: data, encoding: .utf8) {
                print("\n--- CODE VIEW START ---")
                print(textOutput)
                print("--- CODE VIEW END ---\n")
            } else {
                print("❌ Unreadable asset encoding detected.")
            }
        }
        
        task.resume()
        semaphore.wait()
    }
}

// MARK: - Interactive CLI Engine Execution Entrypoint

func getTerminalInput(prompt: String) -> String {
    print(prompt, terminator: "")
    fflush(stdout)
    return readLine()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

print("🖥️  WELCOME TO GITHUB CODE WORKSPACE APP (SWIFT CLI)")
let ownerInput = getTerminalInput(prompt: "Enter Owner/Org name: ")
let repoInput = getTerminalInput(prompt: "Enter Repository name: ")
var branchInput = getTerminalInput(prompt: "Enter Target Branch [default: main]: ")
if branchInput.isEmpty { branchInput = "main" }
let tokenInput = getTerminalInput(prompt: "Enter GitHub Token (Leave blank for public repos): ")

let app = CodeWorkspaceApp(token: tokenInput.isEmpty ? nil : tokenInput)

if app.loadWorkspaceTree(owner: ownerInput, repo: repoInput, branch: branchInput) {
    var sessionActive = true
    while sessionActive {
        app.renderWorkspaceMenu()
        let selection = getTerminalInput(prompt: "Select index number to read file (or 'q' to quit): ")
        
        if selection.lowercased() == "q" {
            print("👋 Closing active workspace safely.")
            sessionActive = false
        } else if let intIndex = Int(selection) {
            app.streamCodeContent(at: intIndex)
            _ = getTerminalInput(prompt: "Press [Enter] to return to workspace tree browser...")
        } else {
            print("❌ Invalid entry mismatch. Enter a listed integer or 'q'.")
        }
    }
}
