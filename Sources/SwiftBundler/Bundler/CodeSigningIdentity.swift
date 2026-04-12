/// An identity that can be used to codesign a file.
struct CodeSigningIdentity: CustomStringConvertible {
  /// The identity's id, which is the SHA-1 hash of the corresponding
  /// certificate's DER representation.
  var id: String
  /// This is the parsed representation of ``id``, and is the SHA-1 hash of
  /// the corresponding certificate's DER representation.
  var certificateSHA1: [UInt8]
  /// The identity's display name.
  var name: String

  var description: String {
    "'\(name)' (\(id))"
  }
}
