import Foundation

// MARK: - .json File Format
/// The file format that AI agents generate. Users copy a prompt to their AI agent,
/// the agent generates this JSON, and the user imports it into Tokengotchi.
///
/// File extension: `.json`
struct PetFile: Codable {

    /// Pet identity.
    let name: String

    /// Optional palette for colors (var(--key) in SVGs)
    let palette: [String: String]?

    /// Icon context definition (SVG definitions and animation states).
    let icon: PetContext
    
    /// Pet / Main App context definition.
    let pet: PetContext

    enum CodingKeys: String, CodingKey {
        case name, palette, icon, pet, menuBar, dock
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.palette = try container.decodeIfPresent([String: String].self, forKey: .palette)
        
        if let decodedPet = try container.decodeIfPresent(PetContext.self, forKey: .pet) {
            self.pet = decodedPet
        } else {
            self.pet = try container.decode(PetContext.self, forKey: .dock)
        }
        
        if let decodedIcon = try container.decodeIfPresent(PetContext.self, forKey: .icon) {
            self.icon = decodedIcon
        } else if let decodedMenuBar = try container.decodeIfPresent(PetContext.self, forKey: .menuBar) {
            self.icon = decodedMenuBar
        } else {
            self.icon = self.pet
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(palette, forKey: .palette)
        try container.encode(icon, forKey: .icon)
        try container.encode(pet, forKey: .pet)
        try container.encode(icon, forKey: .menuBar)
        try container.encode(pet, forKey: .dock)
    }

    // MARK: - Parsing

    /// Parse a .json file from raw JSON data.
    static func parse(_ jsonData: Data) throws -> PetFile {
        let decoder = JSONDecoder()
        do {
            let file = try decoder.decode(PetFile.self, from: jsonData)
            try file.validate()
            return file
        } catch {
            throw ImportError.invalidFormat(error.localizedDescription)
        }
    }

    /// Parse a .json file from a JSON string.
    static func parse(_ jsonString: String) throws -> PetFile {
        guard let data = jsonString.data(using: .utf8) else {
            throw ImportError.invalidUTF8
        }
        return try parse(data)
    }
    
    // MARK: - Validation
    
    private func validate() throws {
        // Validation rules:
        // 1. Every SVG reference must exist in the context's svgs array.
        // 2. An animation cannot have both tracks and frames.
        // 3. The `svg` property is only allowed if `tracks` is used.
        // 4. Context modes cannot be empty.
        
        if pet.modes.isEmpty {
            throw ImportError.invalidFormat("Pet context must have at least one mode.")
        }
        if icon.modes.isEmpty {
            throw ImportError.invalidFormat("Icon context must have at least one mode.")
        }
        
        try icon.validate()
        try pet.validate()
    }

    // MARK: - Conversion

    /// Convert to a PetConfig.
    func toPetConfig() -> PetConfig {
        PetConfig(name: name)
    }

    /// Convert the pet or icon modes to AnimationClip array for backwards compatibility with PetState.
    func toAnimationClips(forContext contextName: String = "pet") -> [AnimationClip] {
        let targetContext = (contextName == "icon" || contextName == "menuBar") ? icon : pet
        var clips = [AnimationClip]()
        
        for modeConfig in targetContext.modes {
            guard let mode = PetMode(rawValue: modeConfig.id) else { continue }
            
            // Top-level mode animations
            for anim in modeConfig.animations {
                clips.append(AnimationClip(
                    id: anim.id,
                    name: anim.name,
                    description: anim.description,
                    duration: anim.duration,
                    modes: [mode],
                    busySubMode: nil
                ))
            }
            
            // Submode animations
            if let subModes = modeConfig.subModes {
                for sub in subModes {
                    let subModeEnum = BusySubMode(rawValue: sub.id)
                    for anim in sub.animations {
                        clips.append(AnimationClip(
                            id: anim.id,
                            name: anim.name,
                            description: anim.description,
                            duration: anim.duration,
                            modes: [mode],
                            busySubMode: subModeEnum
                        ))
                    }
                }
            }
        }
        return clips
    }

    // MARK: - Errors

    enum ImportError: Error, LocalizedError {
        case invalidUTF8
        case invalidFormat(String)

        var errorDescription: String? {
            switch self {
            case .invalidUTF8:
                return "The file is not valid UTF-8 text."
            case .invalidFormat(let msg):
                return "Invalid pet file format: \(msg)"
            }
        }
    }
}

// MARK: - Context Object
struct PetContext: Codable {
    let svgs: [SVGObject]
    let modes: [Mode]
    
    enum CodingKeys: String, CodingKey {
        case svgs
        case modes
        case states // legacy
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.svgs = try container.decode([SVGObject].self, forKey: .svgs)
        if let modes = try container.decodeIfPresent([Mode].self, forKey: .modes) {
            self.modes = modes
        } else {
            self.modes = try container.decode([Mode].self, forKey: .states)
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(svgs, forKey: .svgs)
        try container.encode(modes, forKey: .modes)
        try container.encode(modes, forKey: .states) // write legacy for compatibility
    }
    
    func validate() throws {
        let definedSvgIds = Set(svgs.compactMap { $0.svg != nil ? $0.id : nil })
        
        // Ensure all reference svgs in the svgs array itself resolve
        for svgObj in svgs {
            if svgObj.svg == nil && !definedSvgIds.contains(svgObj.id) {
                throw PetFile.ImportError.invalidFormat("Missing SVG definition for id '\(svgObj.id)'")
            }
        }
        
        // Validate modes
        for mode in modes {
            try mode.validate(definedSvgIds: definedSvgIds)
        }
    }
    
    func resolveSVG(_ svgObj: SVGObject? = nil) -> String? {
        guard let obj = svgObj else {
            // Return first fully defined SVG as default base
            return svgs.first(where: { $0.svg != nil })?.svg ?? svgs.first?.svg
        }
        if let direct = obj.svg { return direct }
        return svgs.first(where: { $0.id == obj.id && $0.svg != nil })?.svg
    }
    
    func findAnimation(id: String) -> AnimationDef? {
        for mode in modes {
            if let a = mode.animations.first(where: { $0.id == id }) { return a }
            if let subs = mode.subModes {
                for s in subs {
                    if let a = s.animations.first(where: { $0.id == id }) { return a }
                }
            }
        }
        return nil
    }
}

// MARK: - SVG Object
struct SVGObject: Codable {
    let id: String
    let svg: String? // If nil, this is just a reference by id
}

// MARK: - Mode Object
struct Mode: Codable {
    let id: String
    let animations: [AnimationDef]
    let subModes: [Mode]?
    
    enum CodingKeys: String, CodingKey {
        case id
        case animations
        case subModes
        case subStates // legacy
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.animations = try container.decode([AnimationDef].self, forKey: .animations)
        if let subModes = try container.decodeIfPresent([Mode].self, forKey: .subModes) {
            self.subModes = subModes
        } else if let subStates = try container.decodeIfPresent([Mode].self, forKey: .subStates) {
            self.subModes = subStates
        } else {
            self.subModes = nil
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(animations, forKey: .animations)
        try container.encodeIfPresent(subModes, forKey: .subModes)
        try container.encodeIfPresent(subModes, forKey: .subStates) // legacy
    }
    
    func validate(definedSvgIds: Set<String>) throws {
        for anim in animations {
            try anim.validate(definedSvgIds: definedSvgIds)
        }
        if let sub = subModes {
            for s in sub {
                try s.validate(definedSvgIds: definedSvgIds)
            }
        }
    }
}

// MARK: - Animation Definition
struct AnimationDef: Codable {
    let id: String
    let name: String
    let description: String
    let duration: TimeInterval
    let svg: SVGObject? // Optional override SVG, only if tracks is used
    let tracks: [KeyframeTrack]?
    let frames: [String]?
    
    func validate(definedSvgIds: Set<String>) throws {
        if tracks != nil && frames != nil {
            throw PetFile.ImportError.invalidFormat("Animation '\(id)' cannot have both 'tracks' and 'frames'.")
        }
        if frames != nil && svg != nil {
            throw PetFile.ImportError.invalidFormat("Animation '\(id)' cannot have 'svg' (override) when using 'frames'.")
        }
        if let overrideSvg = svg, overrideSvg.svg == nil {
            if !definedSvgIds.contains(overrideSvg.id) {
                throw PetFile.ImportError.invalidFormat("Animation '\(id)' references unknown SVG id '\(overrideSvg.id)'.")
            }
        }
    }
}
