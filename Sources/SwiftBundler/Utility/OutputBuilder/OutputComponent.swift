/// The building block of command-line output.
protocol OutputComponent: CustomStringConvertible {
  /// The component's contents as a string.
  @OutputBuilder var body: String { get }
}

extension OutputComponent {
  var description: String {
    body
  }

  /// Prints the component to standard output.
  func show() {
    print(body.trimmingCharacters(in: .newlines))
  }
}
