import Foundation
import Combine

/// Manages loading, saving, and deleting .json files from disk.
@MainActor
final class PetManager: ObservableObject {
    static let shared = PetManager()

    @Published var availablePets: [PetFile] = []
    
    // The currently active pet's JSON.
    @Published var activePet: PetFile = PetManager.defaultPet()
    
    private let petsDirectory: URL
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        petsDirectory = appSupport.appendingPathComponent("Tokengotchi/Pets", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: petsDirectory, withIntermediateDirectories: true)
        
        loadAllPets()
        loadActivePet()
    }
    
    static func defaultPet() -> PetFile {
        guard let url = Bundle.main.url(forResource: "Kuramon", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let pet = try? PetFile.parse(data) else {
            fatalError("Default pet Kuramon.json not found in bundle resources")
        }
        return pet
    }
    
    func loadAllPets() {
        var diskPets: [PetFile] = []
        if let files = try? FileManager.default.contentsOfDirectory(at: petsDirectory, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                guard let data = try? Data(contentsOf: file),
                      let pet = try? PetFile.parse(data) else {
                    continue
                }
                diskPets.append(pet)
            }
        }
        
        let defaultPet = PetManager.defaultPet()
        let overriddenDefault = diskPets.first(where: { $0.name == defaultPet.name })
        
        var loaded: [PetFile] = []
        // Default pet (or its disk override) is always first
        loaded.append(overriddenDefault ?? defaultPet)
        
        // Append all other custom pets
        for pet in diskPets where pet.name != defaultPet.name {
            loaded.append(pet)
        }
        
        // Deduplicate by name (in case of duplicate files on disk)
        var uniqueNames = Set<String>()
        var deduplicated: [PetFile] = []
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
    
    func setActivePet(_ pet: PetFile) {
        activePet = pet
        UserDefaults.standard.set(pet.name, forKey: "tokengotchi.activePetName")
    }
    
    func savePet(_ pet: PetFile) throws {
        let data = try JSONEncoder().encode(pet)
        // Clean filename
        let safeName = pet.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
        let fileURL = petsDirectory.appendingPathComponent("\(safeName).json")
        try data.write(to: fileURL)
        loadAllPets()
        
        // If we overwrote the active pet, update it
        if activePet.name == pet.name {
            setActivePet(pet)
        }
    }
    
    func deletePet(_ pet: PetFile) {
        let safeName = pet.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
        let fileURL = petsDirectory.appendingPathComponent("\(safeName).json")
        try? FileManager.default.removeItem(at: fileURL)
        loadAllPets()
        
        if activePet.name == pet.name {
            setActivePet(PetManager.defaultPet())
        }
    }
}
