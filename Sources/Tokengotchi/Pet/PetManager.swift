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
    private var defaultPetNames: Set<String> = []
    
    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        petsDirectory = appSupport.appendingPathComponent("Tokengotchi/Pets", isDirectory: true)
        
        try? FileManager.default.createDirectory(at: petsDirectory, withIntermediateDirectories: true)
        
        loadAllPets()
        loadActivePet()
    }
    
    static func defaultPet() -> PetFile {
        if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "pets")?
            .sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            // Prefer Kuramon as the default active pet if it exists
            if let kuramonUrl = urls.first(where: { $0.deletingPathExtension().lastPathComponent == "Kuramon" }),
               let data = try? Data(contentsOf: kuramonUrl),
               let pet = try? PetFile.parse(data) {
                return pet
            }
            for url in urls {
                if let data = try? Data(contentsOf: url),
                   let pet = try? PetFile.parse(data) {
                    return pet
                }
            }
        }
        
        // Fallback for root bundle resources or default
        let url = Bundle.main.url(forResource: "Kuramon", withExtension: "json")
        guard let finalUrl = url,
              let data = try? Data(contentsOf: finalUrl),
              let pet = try? PetFile.parse(data) else {
            fatalError("Default pet Kuramon.json not found in bundle resources")
        }
        return pet
    }
    
    func loadAllPets() {
        // 1. Load custom/modified pets from disk
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
        
        // 2. Load all bundled pets from bundle's "pets" subdirectory
        var bundledPets: [PetFile] = []
        if let urls = Bundle.main.urls(forResourcesWithExtension: "json", subdirectory: "pets") {
            for url in urls {
                guard let data = try? Data(contentsOf: url),
                      let pet = try? PetFile.parse(data) else {
                    continue
                }
                bundledPets.append(pet)
            }
        }
        
        // Ensure default pet Kuramon is always present (fallback if not in subdirectory)
        let defaultPet = PetManager.defaultPet()
        if !bundledPets.contains(where: { $0.name == defaultPet.name }) {
            bundledPets.append(defaultPet)
        }
        
        // Cache default pet names
        self.defaultPetNames = Set(bundledPets.map { $0.name })
        
        var loaded: [PetFile] = []
        
        // 3. Add default pet (or its disk override) first
        let defaultOverride = diskPets.first(where: { $0.name == defaultPet.name })
        loaded.append(defaultOverride ?? defaultPet)
        
        // 4. Add other bundled pets (or their disk overrides)
        for bundled in bundledPets where bundled.name != defaultPet.name {
            let override = diskPets.first(where: { $0.name == bundled.name })
            loaded.append(override ?? bundled)
        }
        
        // 5. Add custom disk pets (not matching any bundled pet name)
        for disk in diskPets {
            let isBundled = bundledPets.contains(where: { $0.name == disk.name })
            if !isBundled {
                loaded.append(disk)
            }
        }
        
        // Deduplicate by name (in case of duplicate files)
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
    
    func isDefaultPet(_ name: String) -> Bool {
        return defaultPetNames.contains(name)
    }
    
    func hasLocalOverride(_ name: String) -> Bool {
        let safeName = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
        let fileURL = petsDirectory.appendingPathComponent("\(safeName).json")
        return FileManager.default.fileExists(atPath: fileURL.path)
    }
    
    func resetPet(_ pet: PetFile) {
        let safeName = pet.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
        let fileURL = petsDirectory.appendingPathComponent("\(safeName).json")
        try? FileManager.default.removeItem(at: fileURL)
        loadAllPets()
        
        // Update activePet if it was overridden and we just reset it
        if activePet.name == pet.name {
            if let reverted = availablePets.first(where: { $0.name == pet.name }) {
                setActivePet(reverted)
            } else {
                setActivePet(PetManager.defaultPet())
            }
        }
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
        if isDefaultPet(pet.name) {
            return
        }
        let safeName = pet.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: "\\", with: "-")
        let fileURL = petsDirectory.appendingPathComponent("\(safeName).json")
        try? FileManager.default.removeItem(at: fileURL)
        loadAllPets()
        
        if activePet.name == pet.name {
            setActivePet(PetManager.defaultPet())
        }
    }
}
