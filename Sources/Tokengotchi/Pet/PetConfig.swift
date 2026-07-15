import Foundation

// MARK: - Pet Config
// Simplified to just the identity properties from the .json file
struct PetConfig: Codable, Equatable {
    var name: String
    
    // MARK: Default pet
    static var `default`: PetConfig {
        guard let url = Bundle.main.url(forResource: "Kuramon", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? PetFile.parse(data) else {
            return PetConfig(name: "Fallback")
        }
        return file.toPetConfig()
    }
    
    // MARK: CodingKeys
    enum CodingKeys: String, CodingKey {
        case name
    }
}
