import Foundation

// MARK: - Pet Config (JSON DSL)
// This is what the user's AI agent generates via the custom prompt.
struct PetConfig: Codable, Equatable {
    var name: String
    var baseColor: String           // Hex color, e.g. "#FF6B6B"
    var eyeColor: String            // Hex color
    var personality: Personality
    var accessories: [String]       // IDs from AccessoryRegistry
    var walkSpeed: Double           // 0.5 – 2.0
    var auraColor: String           // Hex color, glow effect
    var backgroundTheme: BackgroundTheme
    var shape: PetShape             // Physical silhouette

    enum Personality: String, Codable, CaseIterable {
        case calm, energetic, mischievous, sleepy
    }

    enum BackgroundTheme: String, Codable, CaseIterable {
        case forest, galaxy, ocean, sunset, minimal
    }

    enum PetShape: String, Codable, CaseIterable {
        case classic
    }

    // MARK: Default pet
    static let `default` = PetConfig(
        name: "Pixel",
        baseColor: "#7C6AF5",
        eyeColor: "#FFE66D",
        personality: .energetic,
        accessories: [],
        walkSpeed: 1.0,
        auraColor: "#A29BFE",
        backgroundTheme: .galaxy,
        shape: .classic
    )

    // MARK: CodingKeys (camelCase JSON)
    enum CodingKeys: String, CodingKey {
        case name
        case baseColor = "base_color"
        case eyeColor = "eye_color"
        case personality
        case accessories
        case walkSpeed = "walk_speed"
        case auraColor = "aura_color"
        case backgroundTheme = "background_theme"
        case shape
    }
}

// MARK: - Accessory Registry
struct AccessoryRegistry {
    struct Item {
        let id: String
        let name: String
        let icon: String    // SF Symbol
        let cost: Int
        let levelRequired: Int
    }

    static let all: [Item] = [
        Item(id: "wizard_hat",   name: "Wizard Hat",     icon: "cone.fill",        cost: 50,  levelRequired: 3),
        Item(id: "crown",        name: "Crown",           icon: "crown.fill",       cost: 200, levelRequired: 10),
        Item(id: "glasses",      name: "Cool Glasses",    icon: "eyeglasses",       cost: 30,  levelRequired: 2),
        Item(id: "scarf",        name: "Scarf",           icon: "wind",             cost: 40,  levelRequired: 2),
        Item(id: "cape",         name: "Hero Cape",       icon: "flag.fill",        cost: 100, levelRequired: 5),
        Item(id: "headphones",   name: "Headphones",      icon: "headphones",       cost: 60,  levelRequired: 4),
        Item(id: "antenna",      name: "AI Antenna",      icon: "antenna.radiowaves.left.and.right", cost: 80, levelRequired: 6),
        Item(id: "halo",         name: "Halo",            icon: "circle.dashed",    cost: 150, levelRequired: 8),
        Item(id: "sunglasses",   name: "Sunglasses",      icon: "sun.max.fill",     cost: 45,  levelRequired: 3),
    ]
}
