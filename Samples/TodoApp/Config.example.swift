import Foundation

/// Configuration for InsForge connection
///
/// SETUP INSTRUCTIONS:
/// 1. Copy this file to Config.swift:
///    cp Sources/Config.example.swift Sources/Config.swift
///
/// 2. Edit Config.swift and replace the values below with your actual InsForge details
///
/// 3. Config.swift is in .gitignore and will not be committed to git
///
enum Config {
    /// Your InsForge instance URL
    /// Example: "https://your-project.insforge.com"
    static let insForgeURL = "https://your-project.insforge.com"

    /// Your InsForge API key
    /// Get this from your InsForge dashboard
    static let apiKey = "your-api-key-here"
}

