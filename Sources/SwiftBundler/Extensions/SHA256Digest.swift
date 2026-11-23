import Crypto

extension SHA256Digest {
  /// Converts a SHA256 digest to a hexadecimal string.
  func hex() -> String {
    withUnsafeBytes { buffer in
      Array<UInt8>(buffer)
    }.hex()
  }
}
