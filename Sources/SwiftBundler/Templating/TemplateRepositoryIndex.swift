import Foundation

/// Swift Bundler's index of the template repositories that it manages.
struct TemplateRepositoryIndex: Codable {
  static let currentSchema = 1

  var schema: Int
  var repositories: [TemplateRepository]
}
