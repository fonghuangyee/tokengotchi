import Foundation

// MARK: - Pet Config
// Simplified to just the identity properties from the .tgpet file
struct PetConfig: Codable, Equatable {
    var name: String
    
    // MARK: Default pet
    static var `default`: PetConfig {
        guard let data = DefaultPetData.jsonString.data(using: .utf8),
              let file = try? JSONDecoder().decode(TGPetFile.self, from: data) else {
            return PetConfig(name: "Fallback")
        }
        return file.toPetConfig()
    }
    
    // MARK: CodingKeys
    enum CodingKeys: String, CodingKey {
        case name
    }
}
