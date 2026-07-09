import Foundation
import Combine

/// Manages loading, saving, and deleting .tgpet files from disk.
@MainActor
final class PetManager: ObservableObject {
    static let shared = PetManager()

    @Published var availablePets: [TGPetFile] = []
    
    // The currently active pet's JSON.
    @Published var activePet: TGPetFile = PetManager.defaultPet()
    
    private let petsDirectory: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        petsDirectory = appSupport.appendingPathComponent("Tokengotchi/Pets", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: petsDirectory, withIntermediateDirectories: true)
        
        loadAllPets()
        loadActivePet()
    }
    
    static func defaultPet() -> TGPetFile {
        let data = DefaultPetData.jsonString.data(using: .utf8)!
        return try! TGPetFile.parse(data)
    }
    
    func loadAllPets() {
        var loaded: [TGPetFile] = []
        
        // Always include the default pet
        loaded.append(PetManager.defaultPet())
        
        guard let files = try? FileManager.default.contentsOfDirectory(at: petsDirectory, includingPropertiesForKeys: nil) else {
            availablePets = loaded
            return
        }
        
        for file in files where file.pathExtension == "tgpet" {
            guard let data = try? Data(contentsOf: file),
                  let pet = try? TGPetFile.parse(data) else {
                continue
            }
            loaded.append(pet)
        }
        
        // Deduplicate by name
        var uniqueNames = Set<String>()
        var deduplicated: [TGPetFile] = []
        for p in loaded {
            if !uniqueNames.contains(p.name) {
                uniqueNames.insert(p.name)
                deduplicated.append(p)
            }
        }
        
        availablePets = deduplicated
    }
    
    func loadActivePet() {
        guard let savedName = UserDefaults.standard.string(forKey: "tokengotchi.activePetName"),
              let found = availablePets.first(where: { $0.name == savedName }) else {
            activePet = PetManager.defaultPet()
            return
        }
        activePet = found
    }
    
    func setActivePet(_ pet: TGPetFile) {
        activePet = pet
        UserDefaults.standard.set(pet.name, forKey: "tokengotchi.activePetName")
    }
    
    func savePet(_ pet: TGPetFile) throws {
        let data = try JSONEncoder().encode(pet)
        // Clean filename
        let safeName = pet.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
        let fileURL = petsDirectory.appendingPathComponent("\(safeName).tgpet")
        try data.write(to: fileURL)
        loadAllPets()
        
        // If we overwrote the active pet, update it
        if activePet.name == pet.name {
            setActivePet(pet)
        }
    }
    
    func deletePet(_ pet: TGPetFile) {
        if pet.name == PetManager.defaultPet().name {
            return // Don't delete default
        }
        let safeName = pet.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
        let fileURL = petsDirectory.appendingPathComponent("\(safeName).tgpet")
        try? FileManager.default.removeItem(at: fileURL)
        loadAllPets()
        
        if activePet.name == pet.name {
            setActivePet(PetManager.defaultPet())
        }
    }
}
