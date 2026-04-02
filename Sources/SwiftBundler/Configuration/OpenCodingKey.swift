protocol OpenCodingKey: CodingKey {
  init(_ stringValue: String)
}

extension OpenCodingKey {
  init?(stringValue: String) {
    self.init(stringValue)
  }
}
