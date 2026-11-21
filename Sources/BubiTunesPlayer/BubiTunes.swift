import Foundation

public enum BubiTunes {
  public static func run(
    arguments: [String],
    makeSynth: @escaping (Int) throws -> any OPNASynthesizer
  ) -> Int32 {
    if arguments.first == "--help" || arguments.first == "-h" {
      print("Usage: bubitunes [--] [FILE.vgm | FILE.vgz | FOLDER ...]")
      return 0
    }
    let paths = arguments.first == "--" ? Array(arguments.dropFirst()) : arguments

    #if os(macOS)
    do {
      return try PlayerSession(paths: paths, makeSynth: makeSynth).run()
    } catch {
      FileHandle.standardError.write(Data((terminalText(error.localizedDescription) + "\n").utf8))
      return 1
    }
    #else
    print("BubiTunes audio output currently requires macOS.")
    return 1
    #endif
  }
}

func terminalText(_ text: String) -> String {
  String(String.UnicodeScalarView(text.unicodeScalars.filter {
    $0.properties.generalCategory != .control && $0.properties.generalCategory != .format
  }))
}
