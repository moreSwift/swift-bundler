import ArgumentParser
import Foundation
import TOMLKit
import Version

/// The configuration for a template in a template repository.
@Configuration
struct TemplateConfiguration: Codable {
  /// The path to the template.
  var path: String

  /// A short description of the template.
  var description: String

  /// A base template that this template inherits from. The base template gets
  /// applied first, and then the template gets applied as an overlay on top.
  var base: Template.Name?

  /// The list of supported platforms.
  var platforms: [String]?

  /// The minimum Swift version required to use the template.
  var minimumSwiftVersion: Version?

  /// The system dependencies required by this template (keyed by the
  /// user-facing dependency name).
  var systemDependencies: [String: SystemDependency]?

  /// The visibility of the template. Defaults to public.
  var visibility: Visibility?

  /// Optional overlays that users can enable when using a template. This allows
  /// templates to provide opt-in features such as VSCode support.
  @ExcludeFromFlat
  var optionalOverlays: [String: OptionalOverlay]?

  @Aggregate("optionalOverlays")
  func processOptionalOverlays(with context: ConfigurationFlattener.Context)
    throws(ConfigurationFlattener.Error)
    -> [OptionalOverlay.Name: OptionalOverlay]
  {
    try ConfigurationFlattener.Error.catch {
      var overlays: [OptionalOverlay.Name: OptionalOverlay] = [:]
      for (name, overlay) in self.optionalOverlays ?? [:] {
        guard let name = OptionalOverlay.Name(name) else {
          throw TemplateRepositoryManager.ErrorMessage.invalidOptionalOverlayName(name)
        }
        overlays[name] = overlay
      }
      return overlays
    }
  }

  @Configuration
  struct OptionalOverlay: Codable {
    /// The template that this overlay applies.
    var template: Template.Name

    /// A description of this overlay.
    var description: String

    /// The question that interactive project creation flows should ask users
    /// when asking whether to enable this overlay or not. If `nil`, interactive
    /// flows may skip this overlay.
    var question: String?
  }

  /// The visibility of a template.
  enum Visibility: String, Codable, TriviallyFlattenable {
    /// A template visible to users of this template repository.
    case `public`

    /// A template hidden from users of this template repository. Generally
    /// only usable as the base template for another template.
    case `internal`
  }
}

extension TemplateConfiguration.OptionalOverlay {
  /// Am optional overlay name. Only alphanumeric ASCII characters, hyphens,
  /// and underscores are allowed. Leading hyphens are disallowed.
  struct Name: Codable, Hashable, Sendable, CustomStringConvertible,
    ExpressibleByArgument, TriviallyFlattenable
  {
    /// We need the same validation as a template repository name, so we just
    /// use a template repository name under the hood.
    private var _name: TemplateRepository.Name

    /// The underlying validated name.
    var name: String {
      _name.name
    }

    /// Creates a validated optional overlay name.
    /// - Returns: `nil` if the name is invalid.
    init?(_ name: String) {
      guard let name = TemplateRepository.Name(name) else {
        return nil
      }
      _name = name
    }

    init?(argument: String) {
      guard let name = TemplateRepository.Name(argument: argument) else {
        return nil
      }
      _name = name
    }

    var description: String {
      _name.description
    }

    // newtype support would be great right about now...

    init(from decoder: any Decoder) throws {
      do {
        _name = try TemplateRepository.Name(from: decoder)
      } catch let error as TemplateRepositoryManager.Error {
        switch error.message {
          case .invalidTemplateRepositoryName(let name):
            throw TemplateRepositoryManager.Error(
              .invalidOptionalOverlayName(name)
            )
          default:
            throw error
        }
      }
    }

    func encode(to encoder: any Encoder) throws {
      try _name.encode(to: encoder)
    }
  }
}
