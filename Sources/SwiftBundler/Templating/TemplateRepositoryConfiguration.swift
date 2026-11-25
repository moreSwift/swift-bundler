import Foundation
import TOMLKit
import Version

/// The configuration for a template repository.
@Configuration
struct TemplateRepositoryConfiguration: Codable {
  /// The configuration file's Swift Bundler compatibility.
  var configVersion: Version

  /// The configuration for each template in the template repository. Maps
  /// template name to template configuration.
  @ExcludeFromFlat
  var templates: [String: TemplateConfiguration]?

  /// Validate the template names (by converting from String to Template.Name),
  /// and detect other misconfigurations such as ghost 'base' template references
  /// and 'base' inheritance cycles.
  @Aggregate("templates")
  func processTemplate(with context: ConfigurationFlattener.Context)
    throws(ConfigurationFlattener.Error)
    -> [Template.Name: TemplateConfiguration.Flat]
  {
    try ConfigurationFlattener.Error.catch {
      var templates: [Template.Name: TemplateConfiguration.Flat] = [:]
      for (name, template) in self.templates ?? [:] {
        guard let name = Template.Name(name) else {
          throw TemplateRepositoryManager.ErrorMessage.invalidTemplateName(name)
        }
        templates[name] = try template.flatten(with: context)
      }

      // Detect ghost 'base' references, and 'base' reference cycles
      for (name, template) in templates {
        var path: [Template.Name] = [name]
        var previous = name
        var next = template.base
        while let current = next {
          guard current != name else {
            throw TemplateRepositoryManager.ErrorMessage.selfReferentialTemplate(
              template: name,
              path: path + [current]
            )
          }

          guard !path.contains(current) else {
            // We found a reference cycle, but not for this template. Wait to
            // report the error for the actual offending self-referential template
            break
          }

          path.append(current)

          guard let currentTemplate = templates[current] else {
            throw TemplateRepositoryManager.ErrorMessage.nonExistentBaseTemplate(
              template: previous,
              base: current
            )
          }

          previous = current
          next = currentTemplate.base
        }
      }
      
      return templates
    }
  }

  /// The configuration for the repository's base template.
  struct BaseTemplateConfiguration: Codable {
    var path: String
  }

  /// Loads a configuration from a file.
  static func load(from file: URL) throws(TemplateRepositoryManager.Error) -> Self.Flat {
    try TemplateRepositoryManager.Error.catch(
      withMessage: .failedToLoadTemplateRepositoryConfiguration(file)
    ) {
      let contents = try String(contentsOf: file)

      var decoder = TOMLDecoder()
      decoder.strictDecoding = true
      decoder.userInfo[.decodingMethod] = DecodingMethod.tolerant

      let config = try decoder.decode(Self.self, from: contents)
      return try config.flatten(
        // TODO(stackotter): Redo configuration flattening system so that
        //   arbitrary condition expressions can be injected. This context
        //   is very specific to apps, and doesn't make any sense for
        //   template repositories. For now I've just used some dummy values
        //   that are absurd enough to hopefully help people track down this
        //   code if they cause any issues.
        with: ConfigurationFlattener.Context(
          platform: .android,
          bundler: .androidAPK,
          architectures: [.armv7]
        )
      )
    }
  }
}
