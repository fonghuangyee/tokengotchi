import Foundation

// MARK: - .json File Format
/// The file format that AI agents generate. Users copy a prompt to their AI agent,
/// the agent generates this JSON, and the user imports it into Tokengotchi.
///
/// File extension: `.json`
struct TGPetFile: Codable {

    /// Pet identity.
    let name: String

    /// Optional palette for colors (var(--key) in SVGs)
    let palette: [String: String]?

    /// Menu Bar context definition (SVG definitions and animation states).
    let menuBar: TGPetContext
    
    /// Dock / Main App context definition.
    let dock: TGPetContext

    enum CodingKeys: String, CodingKey {
        case name, palette, menuBar, dock
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.name = try container.decode(String.self, forKey: .name)
        self.palette = try container.decodeIfPresent([String: String].self, forKey: .palette)
        self.dock = try container.decode(TGPetContext.self, forKey: .dock)
        
        // Fallback to dock if menuBar is missing
        self.menuBar = try container.decodeIfPresent(TGPetContext.self, forKey: .menuBar) ?? self.dock
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(palette, forKey: .palette)
        try container.encode(menuBar, forKey: .menuBar)
        try container.encode(dock, forKey: .dock)
    }

    // MARK: - Parsing

    /// Parse a .json file from raw JSON data.
    static func parse(_ jsonData: Data) throws -> TGPetFile {
        let decoder = JSONDecoder()
        do {
            let file = try decoder.decode(TGPetFile.self, from: jsonData)
            try file.validate()
            return file
        } catch {
            throw ImportError.invalidFormat(error.localizedDescription)
        }
    }

    /// Parse a .json file from a JSON string.
    static func parse(_ jsonString: String) throws -> TGPetFile {
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
        // 4. Context states cannot be empty.
        
        if dock.states.isEmpty {
            throw ImportError.invalidFormat("Dock context must have at least one state.")
        }
        if menuBar.states.isEmpty {
            throw ImportError.invalidFormat("MenuBar context must have at least one state.")
        }
        
        try menuBar.validate()
        try dock.validate()
    }

    // MARK: - Conversion

    /// Convert to a PetConfig.
    func toPetConfig() -> PetConfig {
        PetConfig(name: name)
    }

    /// Convert the dock states to AnimationClip array for backwards compatibility with PetState.
    func toAnimationClips(forContext contextName: String = "dock") -> [AnimationClip] {
        let targetContext = (contextName == "menuBar") ? menuBar : dock
        var clips = [AnimationClip]()
        
        for state in targetContext.states {
            guard let mode = PetMode(rawValue: state.id) else { continue }
            
            // Top-level state animations
            for anim in state.animations {
                clips.append(AnimationClip(
                    id: anim.id,
                    name: anim.name,
                    description: anim.description,
                    duration: anim.duration,
                    modes: [mode],
                    busySubstate: nil
                ))
            }
            
            // Substate animations
            if let subStates = state.subStates {
                for sub in subStates {
                    let substateEnum = BusySubstate(rawValue: sub.id)
                    for anim in sub.animations {
                        clips.append(AnimationClip(
                            id: anim.id,
                            name: anim.name,
                            description: anim.description,
                            duration: anim.duration,
                            modes: [mode],
                            busySubstate: substateEnum
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
struct TGPetContext: Codable {
    let svgs: [TGSVGObject]
    let states: [TGState]
    
    func validate() throws {
        let definedSvgIds = Set(svgs.compactMap { $0.svg != nil ? $0.id : nil })
        
        // Ensure all reference svgs in the svgs array itself resolve
        for svgObj in svgs {
            if svgObj.svg == nil && !definedSvgIds.contains(svgObj.id) {
                throw TGPetFile.ImportError.invalidFormat("Missing SVG definition for id '\(svgObj.id)'")
            }
        }
        
        // Validate states
        for state in states {
            try state.validate(definedSvgIds: definedSvgIds)
        }
    }
    
    func resolveSVG(_ svgObj: TGSVGObject? = nil) -> String? {
        guard let obj = svgObj else {
            // Return first fully defined SVG as default base
            return svgs.first(where: { $0.svg != nil })?.svg ?? svgs.first?.svg
        }
        if let direct = obj.svg { return direct }
        return svgs.first(where: { $0.id == obj.id && $0.svg != nil })?.svg
    }
    
    func findAnimation(id: String) -> TGAnimationDef? {
        for state in states {
            if let a = state.animations.first(where: { $0.id == id }) { return a }
            if let subs = state.subStates {
                for s in subs {
                    if let a = s.animations.first(where: { $0.id == id }) { return a }
                }
            }
        }
        return nil
    }
}

// MARK: - SVG Object
struct TGSVGObject: Codable {
    let id: String
    let svg: String? // If nil, this is just a reference by id
}

// MARK: - State Object
struct TGState: Codable {
    let id: String
    let animations: [TGAnimationDef]
    let subStates: [TGState]?
    
    func validate(definedSvgIds: Set<String>) throws {
        for anim in animations {
            try anim.validate(definedSvgIds: definedSvgIds)
        }
        if let sub = subStates {
            for s in sub {
                try s.validate(definedSvgIds: definedSvgIds)
            }
        }
    }
}

// MARK: - Animation Definition
struct TGAnimationDef: Codable {
    let id: String
    let name: String
    let description: String
    let duration: TimeInterval
    let svg: TGSVGObject? // Optional override SVG, only if tracks is used
    let tracks: [KeyframeTrack]?
    let frames: [String]?
    
    func validate(definedSvgIds: Set<String>) throws {
        if tracks != nil && frames != nil {
            throw TGPetFile.ImportError.invalidFormat("Animation '\(id)' cannot have both 'tracks' and 'frames'.")
        }
        if frames != nil && svg != nil {
            throw TGPetFile.ImportError.invalidFormat("Animation '\(id)' cannot have 'svg' (override) when using 'frames'.")
        }
        if let overrideSvg = svg, overrideSvg.svg == nil {
            if !definedSvgIds.contains(overrideSvg.id) {
                throw TGPetFile.ImportError.invalidFormat("Animation '\(id)' references unknown SVG id '\(overrideSvg.id)'.")
            }
        }
    }
}
