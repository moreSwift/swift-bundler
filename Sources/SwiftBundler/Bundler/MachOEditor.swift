import Foundation
import ErrorKit

enum MachOEditor {
  enum MachOFile {
    case regular(Regular)
    case universal(Universal)

    /// The endianness of a Mach-O file.
    enum Endianness {
      case little
      case big
    }

    /// The offset of a value in a MachOFile (measured in bytes).
    struct Offset {
      var value: Int

      static func + (_ lhs: Self, _ rhs: Int) -> Self {
        Self(value: lhs.value + rhs)
      }
    }

    struct Regular {
      /// The big endian magic number of a 32-bit big endian Mach-O file.
      static let magicNumber32BitBigEndian: UInt32 = 0xfeed_face
      /// The big endian magic number of a 64-bit big endian Mach-O file.
      static let magicNumber64BitBigEndian: UInt32 = 0xfeed_facf
      /// The big endian magic number of a 32-bit little endian Mach-O file.
      static let magicNumber32BitLittleEndian: UInt32 = 0xcefa_edfe
      /// The big endian magic number of a 64-bit little endian Mach-O file.
      static let magicNumber64BitLittleEndian: UInt32 = 0xcffa_edfe

      var endianness: Endianness

      var cpuType: UInt32
      var cpuSubtype: UInt32
      var fileType: UInt32
      var numberOfLoadCommands: UInt32
      var sizeOfLoadCommands: UInt32
      var flags: UInt32
      var loadCommands: [(Offset, LoadCommand)]
    }

    struct Universal {
      static let magicNumber: UInt32 = 0xcafe_babe

      var binaries: [Binary]

      struct Binary {
        var cpuType: UInt32
        var cpuSubtype: UInt32
        var fileOffset: UInt32
        var size: UInt32
        var sectionAlignment: UInt32
      }
    }

    enum LoadCommand {
      case segmentLoad64(SegmentLoad64)
      case other(type: UInt32, remainingBytes: [UInt8])

      struct SegmentLoad64 {
        // swiftlint:disable large_tuple
        typealias SegmentName = (
          UInt8, UInt8, UInt8, UInt8,
          UInt8, UInt8, UInt8, UInt8,
          UInt8, UInt8, UInt8, UInt8,
          UInt8, UInt8, UInt8, UInt8
        )
        // swiftlint:enable large_tuple

        /// The Mach-O load command type of this load command.
        static let commandType: UInt32 = 0x0000_0019

        /// The offset of the ``size`` field within an encoded segment load 64
        /// command.
        static let offsetOfSize: Int = 48

        var segmentName: SegmentName
        var address: UInt64
        var addressSize: UInt64
        var fileOffset: UInt64
        var size: UInt64
        var maximumVirtualMemoryProtections: UInt32
        var initialVirtualMemoryProtections: UInt32
        var numberOfSections: UInt32
        var flags: UInt32

        // The segment name as an array of bytes with the null byte and all
        // following bytes dropped.
        var segmentNameBytes: [UInt8] {
          var bytes: [UInt8] = []
          withUnsafeBytes(of: segmentName) { pointer in
            let pointer = pointer.assumingMemoryBound(to: UInt8.self)
            for index in 0..<MemoryLayout<SegmentName>.stride {
              guard pointer[index] != 0 else {
                return
              }
              bytes.append(pointer[index])
            }
          }
          return bytes
        }

        var segmentNameString: String? {
          let data = Data(segmentNameBytes)
          return String(data: data, encoding: .ascii)
        }
      }
    }
  }

  enum Edit {
    case replace(_ offset: MachOFile.Offset, _ bytes: [UInt8])
  }

  typealias Error = RichError<ErrorMessage>

  enum ErrorMessage: Throwable {
    case failedToReadFile(URL)
    case fileCorrupted(_ reason: String)
    case failedToParseFile(URL)
    case unknownMagicBytes(UInt32)
    case outOfBoundsEdit(Edit, bufferSize: Int)

    var userFriendlyMessage: String {
      switch self {
        case .failedToReadFile(let file):
          return "Failed to read Mach-O file '\(file.relativePath)'"
        case .fileCorrupted(let reason):
          return "File corrupted: \(reason)"
        case .failedToParseFile(let file):
          return "Failed to parse Mach-O file '\(file.relativePath)'"
        case .unknownMagicBytes:
          return "Encountered unknown magic bytes. File may be corrupted"
        case .outOfBoundsEdit(let edit, let bufferSize):
          return """
            Edit '\(edit)' was out-of-bounds when applied to a buffer of size \
            \(bufferSize)
            """
      }
    }
  }

  static func applyEdit(_ edit: Edit, to bytes: inout [UInt8]) throws(Error) {
    switch edit {
      case .replace(let offset, let newBytes):
        let end = offset.value + newBytes.count
        guard end <= bytes.count else {
          throw Error(.outOfBoundsEdit(edit, bufferSize: bytes.count))
        }

        for (index, byte) in newBytes.enumerated() {
          bytes[offset.value + index] = byte
        }
    }
  }

  static func updateFileSize(
    of file: MachOFile,
    to newFileSize: Int
  ) -> [Edit] {
    switch file {
      case .regular(let regularFile):
        for (offset, command) in regularFile.loadCommands {
          guard
            case let .segmentLoad64(segmentLoadCommand) = command,
            segmentLoadCommand.segmentNameString == "__LINKEDIT"
          else {
            continue
          }

          let newSegmentSize = newFileSize - Int(segmentLoadCommand.fileOffset)
          return [
            .replace(
              offset + MachOFile.LoadCommand.SegmentLoad64.offsetOfSize,
              encodeUInt64(
                UInt64(newSegmentSize),
                endianness: regularFile.endianness
              )
            )
          ]
        }
        return []
      case .universal:
        // Not supported at this time.
        return []
    }
  }

  private static func encodeUInt64(
    _ value: UInt64,
    endianness: MachOFile.Endianness
  ) -> [UInt8] {
    let bigEndianBytes = [
      UInt8(truncatingIfNeeded: value >> 56),
      UInt8(truncatingIfNeeded: value >> 48),
      UInt8(truncatingIfNeeded: value >> 40),
      UInt8(truncatingIfNeeded: value >> 32),
      UInt8(truncatingIfNeeded: value >> 24),
      UInt8(truncatingIfNeeded: value >> 16),
      UInt8(truncatingIfNeeded: value >> 8),
      UInt8(truncatingIfNeeded: value),
    ]

    switch endianness {
      case .big:
        return bigEndianBytes
      case .little:
        return bigEndianBytes.reversed()
    }
  }

  static func parseMachOFile(_ file: URL) throws(Error) -> MachOFile {
    let data: Data
    do {
      data = try Data(contentsOf: file)
    } catch {
      throw Error(.failedToReadFile(file), cause: error)
    }

    do {
      return try parseMachOFile(Array(data))
    } catch {
      throw Error(.failedToParseFile(file), cause: error)
    }
  }

  static func parseMachOFile(_ bytes: [UInt8]) throws(Error) -> MachOFile {
    var buffer = Buffer(bytes: bytes)

    guard let magicBytes = buffer.readUInt32() else {
      throw Error(.fileCorrupted("File too short to have magic bytes"))
    }

    let file: MachOFile
    switch magicBytes {
      case MachOFile.Regular.magicNumber32BitBigEndian:
        let regularFile = try parseRegularMachOFile(
          &buffer,
          is64Bit: false,
          endianness: .big
        )
        file = .regular(regularFile)
      case MachOFile.Regular.magicNumber64BitBigEndian:
        let regularFile = try parseRegularMachOFile(
          &buffer,
          is64Bit: true,
          endianness: .big
        )
        file = .regular(regularFile)
      case MachOFile.Regular.magicNumber32BitLittleEndian:
        let regularFile = try parseRegularMachOFile(
          &buffer,
          is64Bit: false,
          endianness: .little
        )
        file = .regular(regularFile)
      case MachOFile.Regular.magicNumber64BitLittleEndian:
        let regularFile = try parseRegularMachOFile(
          &buffer,
          is64Bit: true,
          endianness: .little
        )
        file = .regular(regularFile)
      case MachOFile.Universal.magicNumber:
        let universalFile = try parseUniversalMachOFile(&buffer)
        file = .universal(universalFile)
      default:
        throw Error(.unknownMagicBytes(magicBytes))
    }

    return file
  }

  static func parseRegularMachOFile(
    _ buffer: inout Buffer,
    is64Bit: Bool,
    endianness: MachOFile.Endianness
  ) throws(Error) -> MachOFile.Regular {
    guard
      let cpuType = buffer.readUInt32(endianness: endianness),
      let cpuSubtype = buffer.readUInt32(endianness: endianness),
      let fileType = buffer.readUInt32(endianness: endianness),
      let numberOfLoadCommands = buffer.readUInt32(endianness: endianness),
      let sizeOfLoadCommands = buffer.readUInt32(endianness: endianness),
      let flags = buffer.readUInt32(endianness: endianness),
      // For 64-bit binaries, there's an additional 4 byte reserved field
      !is64Bit || buffer.readUInt32(endianness: endianness) != nil
    else {
      throw Error(.fileCorrupted("Mach-O header too short"))
    }

    var loadCommands: [(MachOFile.Offset, MachOFile.LoadCommand)] = []
    for _ in 0..<Int(numberOfLoadCommands) {
      let offset = buffer.currentOffset

      guard
        let commandType = buffer.readUInt32(endianness: endianness),
        let commandSize = buffer.readUInt32(endianness: endianness),
        let commandBytes = buffer.readBytes(Int(commandSize) - 8)
      else {
        throw Error(.fileCorrupted("Malformed load command"))
      }

      guard commandType == MachOFile.LoadCommand.SegmentLoad64.commandType else {
        let command = MachOFile.LoadCommand.other(
          type: commandType,
          remainingBytes: commandBytes
        )
        loadCommands.append((offset, command))
        continue
      }

      var commandBuffer = Buffer(bytes: commandBytes)

      guard
        let segmentName = commandBuffer.readBytes(16),
        let address = commandBuffer.readUInt64(endianness: endianness),
        let addressSize = commandBuffer.readUInt64(endianness: endianness),
        let fileOffset = commandBuffer.readUInt64(endianness: endianness),
        let fileSize = commandBuffer.readUInt64(endianness: endianness),
        let maximumVirtualMemoryProtections = commandBuffer.readUInt32(endianness: endianness),
        let initialVirtualMemoryProtections = commandBuffer.readUInt32(endianness: endianness),
        let numberOfSections = commandBuffer.readUInt32(endianness: endianness),
        let flags = commandBuffer.readUInt32(endianness: endianness)
      else {
        throw Error(.fileCorrupted("Malformed Segment Load 64 load command"))
      }

      let command = MachOFile.LoadCommand.SegmentLoad64(
        segmentName: segmentName.withUnsafeBytes { pointer in
          pointer.assumingMemoryBound(
            to: MachOFile.LoadCommand.SegmentLoad64.SegmentName.self
          ).baseAddress!.pointee
        },
        address: address,
        addressSize: addressSize,
        fileOffset: fileOffset,
        size: fileSize,
        maximumVirtualMemoryProtections: maximumVirtualMemoryProtections,
        initialVirtualMemoryProtections: initialVirtualMemoryProtections,
        numberOfSections: numberOfSections,
        flags: flags
      )
      loadCommands.append((offset, .segmentLoad64(command)))
    }

    return MachOFile.Regular(
      endianness: endianness,
      cpuType: cpuType,
      cpuSubtype: cpuSubtype,
      fileType: fileType,
      numberOfLoadCommands: numberOfLoadCommands,
      sizeOfLoadCommands: sizeOfLoadCommands,
      flags: flags,
      loadCommands: loadCommands
    )
  }

  static func parseUniversalMachOFile(
    _ buffer: inout Buffer
  ) throws(Error) -> MachOFile.Universal {
    guard let numberOfBinaries = buffer.readUInt32() else {
      throw Error(.fileCorrupted("Malformed universal header"))
    }

    var binaries: [MachOFile.Universal.Binary] = []
    for _ in 0..<numberOfBinaries {
      guard
        let cpuType = buffer.readUInt32(),
        let cpuSubtype = buffer.readUInt32(),
        let fileOffset = buffer.readUInt32(),
        let size = buffer.readUInt32(),
        let sectionAlignment = buffer.readUInt32()
      else {
        throw Error(.fileCorrupted("Malformed universal binary header"))
      }

      let binary = MachOFile.Universal.Binary(
        cpuType: cpuType,
        cpuSubtype: cpuSubtype,
        fileOffset: fileOffset,
        size: size,
        sectionAlignment: sectionAlignment
      )
      binaries.append(binary)
    }

    return MachOFile.Universal(binaries: binaries)
  }

  struct Buffer {
    var index: Int = 0
    var bytes: [UInt8]

    var currentOffset: MachOFile.Offset {
      MachOFile.Offset(value: index)
    }

    mutating func readUInt32(endianness: MachOFile.Endianness = .big) -> UInt32? {
      let stride = MemoryLayout<UInt32>.stride
      guard index + stride <= bytes.count else {
        return nil
      }

      // Convert to array to avoid stupid slice indexing boilerplate
      let slice = Array(bytes[index..<(index + stride)])
      index += stride
      switch endianness {
        case .big:
          return (UInt32(slice[0]) << 24)
            | (UInt32(slice[1]) << 16)
            | (UInt32(slice[2]) << 8)
            | UInt32(slice[3])
        case .little:
          return (UInt32(slice[3]) << 24)
            | (UInt32(slice[2]) << 16)
            | (UInt32(slice[1]) << 8)
            | UInt32(slice[0])
      }
    }

    mutating func readUInt64(endianness: MachOFile.Endianness = .big) -> UInt64? {
      guard
        let firstHalf = readUInt32(endianness: endianness),
        let secondHalf = readUInt32(endianness: endianness)
      else {
        return nil
      }

      switch endianness {
        case .big:
          return (UInt64(firstHalf) << 32) | UInt64(secondHalf)
        case .little:
          return (UInt64(secondHalf) << 32) | UInt64(firstHalf)
      }
    }

    mutating func readBytes(_ count: Int) -> [UInt8]? {
      guard index + count <= bytes.count else {
        return nil
      }

      let requestedBytes = Array(bytes[index..<(index + count)])
      index += count
      return requestedBytes
    }
  }
}
