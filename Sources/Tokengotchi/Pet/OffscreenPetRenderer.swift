import AppKit

struct OffscreenPetRenderer {

    /// Render a single frame for the given clip ID (menu-bar size: 22×22).
    static func renderFrame(
        clipID: String, pet: TGPetFile, time: TimeInterval,
        stamina: Double? = nil, modelName: String? = nil,
        isTemplate: Bool = false,
        contextName: String = "menuBar",
        targetSize: NSSize = NSSize(width: 22, height: 22)
    ) -> NSImage {
        let size  = targetSize
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.set()
            rect.fill()

            // Flip: SVG (Y-down) → AppKit (Y-up)
            NSGraphicsContext.current?.saveGraphicsState()
            let flip = NSAffineTransform()
            flip.translateX(by: 0, yBy: size.height)
            flip.scaleX(by: 1, yBy: -1)
            flip.concat()

            // 1. Resolve animation
            let duration: TimeInterval
            let tracks: [KeyframeTrack]
            let svgString: String
            let targetContext = contextName == "menuBar" ? pet.menuBar : pet.dock

            var resolvedAnimation = targetContext.findAnimation(id: clipID)
            
            // If not found in target context, the clipID is likely from another context (e.g. dock).
            // Find its corresponding state in dock, and pick the matching state in targetContext.
            if resolvedAnimation == nil && contextName != "dock" {
                var topLevelStateId: String?
                var subStateId: String?
                
                for state in pet.dock.states {
                    if state.animations.contains(where: { $0.id == clipID }) {
                        topLevelStateId = state.id
                        break
                    }
                    if let subs = state.subStates {
                        if let sub = subs.first(where: { s in s.animations.contains(where: { $0.id == clipID }) }) {
                            topLevelStateId = state.id
                            subStateId = sub.id
                            break
                        }
                    }
                }
                
                if let topId = topLevelStateId {
                    if let targetState = targetContext.states.first(where: { $0.id == topId }) {
                        if let subId = subStateId,
                           let targetSub = targetState.subStates?.first(where: { $0.id == subId }),
                           let anim = targetSub.animations.first {
                            resolvedAnimation = anim
                        } else {
                            resolvedAnimation = targetState.animations.first
                        }
                    }
                }
            }

            if let animation = resolvedAnimation {
                duration = animation.duration
                if let frames = animation.frames, !frames.isEmpty {
                    let normalizedTime = time.truncatingRemainder(dividingBy: duration)
                    let progress  = normalizedTime / duration
                    let index     = Int(progress * Double(frames.count))
                    let safeIndex = min(max(index, 0), frames.count - 1)
                    svgString = frames[safeIndex]
                    tracks    = []
                } else {
                    svgString = targetContext.resolveSVG(animation.svg) ?? ""
                    tracks    = animation.tracks ?? []
                }
            } else {
                duration  = 1.0
                svgString = targetContext.resolveSVG(nil) ?? ""
                tracks    = [KeyframeTrack(targetId: "body", keyframes: [
                    Keyframe(time: 0,   ty: 0, sx: 1,    sy: 1),
                    Keyframe(time: 0.5, ty: 3, sx: 1.05, sy: 0.95),
                    Keyframe(time: 1.0, ty: 0, sx: 1,    sy: 1)
                ])]
            }

            // 2. Parse SVG
            guard let doc = try? SVGParser.parseSVG(svgString) else { return true }

            // 3. Evaluate keyframe transforms
            let transforms = AnimationEvaluator.evaluate(tracks: tracks, duration: duration, time: time)

            // 4. Scale to 22×22
            let scaleResult = SVGParser.scaleLayer(doc.root, toFit: rect, padding: 1)

            // 5. Draw
            NSGraphicsContext.current?.saveGraphicsState()
            drawLayer(scaleResult.layer, transforms: transforms, pet: pet,
                      scale: scaleResult.scale, defs: doc.defs)
            NSGraphicsContext.current?.restoreGraphicsState()
            NSGraphicsContext.current?.restoreGraphicsState()

            return true
        }
        image.isTemplate = isTemplate
        return image
    }

    // MARK: - Layer Rendering

    private static func drawLayer(_ layer: SVGLayer,
                                  transforms: [String: LayerTransform],
                                  pet: TGPetFile,
                                  scale: CGFloat,
                                  defs: SVGDefinitions) {
        let t = transforms[layer.id] ?? .identity

        NSGraphicsContext.current?.saveGraphicsState()

        let bb = SVGParser.boundingBox(of: layer)
        let cx = bb.midX, cy = bb.midY
        let xform = NSAffineTransform()
        xform.translateX(by: cx + t.tx * scale, yBy: cy + t.ty * scale)
        xform.rotate(byDegrees: t.rotate)
        xform.scaleX(by: t.sx, yBy: t.sy)
        xform.translateX(by: -cx, yBy: -cy)
        xform.concat()

        if layer.opacity < 1.0, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setAlpha(layer.opacity)
        }

        for element in layer.elements {
            drawElement(element, pet: pet, defs: defs)
        }
        for child in layer.children {
            drawLayer(child, transforms: transforms, pet: pet, scale: scale, defs: defs)
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // MARK: - Element Rendering

    private static func drawElement(_ element: SVGElement, pet: TGPetFile, defs: SVGDefinitions) {
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        if element.opacity < 1.0, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setAlpha(element.opacity)
        }

        let bezier = NSBezierPath()
        SVGParser.appendCGPath(element.path, to: bezier)
        bezier.windingRule   = element.fillRule == .evenOdd ? .evenOdd : .nonZero
        bezier.lineWidth     = element.strokeWidth
        bezier.lineCapStyle  = element.strokeLinecap  == .round  ? .round  :
                               element.strokeLinecap  == .square ? .square : .butt
        bezier.lineJoinStyle = element.strokeLinejoin == .round  ? .round  :
                               element.strokeLinejoin == .bevel  ? .bevel  : .miter
        bezier.miterLimit    = element.strokeMiterLimit

        if !element.strokeDashArray.isEmpty {
            var dash = element.strokeDashArray
            bezier.setLineDash(&dash, count: dash.count, phase: element.strokeDashOffset)
        }

        // Fill
        switch element.fill {
        case .color(let s):
            if s != "none" {
                let resolved = resolveColorString(s, palette: pet.palette)
                if let color = NSColor(svgString: resolved)?
                    .withAlphaComponent((NSColor(svgString: resolved)?.alphaComponent ?? 1) * element.fillOpacity) {
                    color.setFill()
                    bezier.fill()
                }
            }
        case .gradient(let id):
            if let gradDef = defs.gradients[id], let ctx = NSGraphicsContext.current?.cgContext {
                drawGradient(gradDef, bezier: bezier, fillOpacity: element.fillOpacity,
                             palette: pet.palette, ctx: ctx)
            }
        }

        // Stroke
        switch element.stroke {
        case .color(let s):
            if s != "none" {
                let resolved = resolveColorString(s, palette: pet.palette)
                if let color = NSColor(svgString: resolved)?
                    .withAlphaComponent((NSColor(svgString: resolved)?.alphaComponent ?? 1) * element.strokeOpacity) {
                    color.setStroke()
                    bezier.stroke()
                }
            }
        case .gradient:
            break  // stroke gradients not applied in menu-bar renderer for performance
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // MARK: - Gradient

    private static func drawGradient(_ gradDef: SVGGradientDef,
                                     bezier: NSBezierPath,
                                     fillOpacity: CGFloat,
                                     palette: [String: String]?,
                                     ctx: CGContext) {
        let stops: [SVGGradientStop]
        switch gradDef {
        case .linear(_, _, _, _, let s, _): stops = s
        case .radial(_, _, _, _, _, let s, _): stops = s
        }
        var cgColors:  [CGColor]  = []
        var locations: [CGFloat]  = []
        for stop in stops {
            let resolved = resolveColorString(stop.color, palette: palette)
            if let base = NSColor(svgString: resolved) {
                cgColors.append(base.withAlphaComponent(base.alphaComponent * stop.opacity * fillOpacity).cgColor)
                locations.append(stop.offset)
            }
        }
        guard !cgColors.isEmpty,
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: cgColors as CFArray, locations: locations)
        else { return }

        ctx.saveGState()
        ctx.addPath(bezier.cgPath)
        ctx.clip()
        let bb   = bezier.bounds
        let opts = CGGradientDrawingOptions([.drawsBeforeStartLocation, .drawsAfterEndLocation])

        switch gradDef {
        case .linear(let x1, let y1, let x2, let y2, _, let us):
            let s = us ? CGPoint(x: x1, y: y1) : CGPoint(x: bb.minX + x1 * bb.width, y: bb.minY + y1 * bb.height)
            let e = us ? CGPoint(x: x2, y: y2) : CGPoint(x: bb.minX + x2 * bb.width, y: bb.minY + y2 * bb.height)
            ctx.drawLinearGradient(gradient, start: s, end: e, options: opts)
        case .radial(let cx, let cy, let r, let fx, let fy, _, let us):
            let c = us ? CGPoint(x: cx, y: cy) : CGPoint(x: bb.minX + cx * bb.width, y: bb.minY + cy * bb.height)
            let f = us ? CGPoint(x: fx, y: fy) : CGPoint(x: bb.minX + fx * bb.width, y: bb.minY + fy * bb.height)
            let rad = us ? r : r * min(bb.width, bb.height)
            ctx.drawRadialGradient(gradient, startCenter: f, startRadius: 0,
                                   endCenter: c, endRadius: rad, options: opts)
        }
        ctx.restoreGState()
    }

    // MARK: - Helpers

    static func resolveColorString(_ string: String, palette: [String: String]?) -> String {
        if string.hasPrefix("var(--") && string.hasSuffix(")") {
            let start = string.index(string.startIndex, offsetBy: 6)
            let end   = string.index(string.endIndex,   offsetBy: -1)
            let key   = String(string[start..<end])
            return palette?[key] ?? string
        }
        return string
    }
}

// MARK: - NSBezierPath CGPath

private extension NSBezierPath {
    var cgPath: CGPath {
        let p = CGMutablePath()
        var pts = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            switch element(at: i, associatedPoints: &pts) {
            case .moveTo:             p.move(to: pts[0])
            case .lineTo:             p.addLine(to: pts[0])
            case .curveTo:            p.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .cubicCurveTo:       p.addCurve(to: pts[2], control1: pts[0], control2: pts[1])
            case .quadraticCurveTo:   p.addQuadCurve(to: pts[1], control: pts[0])
            case .closePath:          p.closeSubpath()
            @unknown default:         break
            }
        }
        return p
    }
}

// MARK: - NSColor SVG colour parsing

extension NSColor {

    /// Parse any SVG colour string: hex (#rgb, #rgba, #rrggbb, #rrggbbaa),
    /// SVG named colours, and `transparent`. Returns nil for "none" / unresolvable.
    convenience init?(svgString: String) {
        let s = svgString.trimmingCharacters(in: .whitespaces).lowercased()
        guard !s.isEmpty, s != "none", s != "currentcolor" else { return nil }

        if s == "transparent" {
            self.init(red: 0, green: 0, blue: 0, alpha: 0)
            return
        }

        if s.hasPrefix("#") {
            let hex = String(s.dropFirst())
            switch hex.count {
            case 3:
                // #rgb → #rrggbb
                let chars = Array(hex)
                let expanded = "\(chars[0])\(chars[0])\(chars[1])\(chars[1])\(chars[2])\(chars[2])"
                self.init(hex6: expanded)
            case 4:
                // #rgba → #rrggbbaa
                let chars = Array(hex)
                let rgb   = "\(chars[0])\(chars[0])\(chars[1])\(chars[1])\(chars[2])\(chars[2])"
                let aPart = "\(chars[3])\(chars[3])"
                guard let a = UInt8(aPart, radix: 16) else { return nil }
                self.init(hex6: rgb, alpha: CGFloat(a) / 255)
            case 6:
                self.init(hex6: hex)
            case 8:
                var rgb: UInt64 = 0
                guard Scanner(string: hex).scanHexInt64(&rgb) else { return nil }
                self.init(
                    red:   CGFloat((rgb & 0xFF000000) >> 24) / 255,
                    green: CGFloat((rgb & 0x00FF0000) >> 16) / 255,
                    blue:  CGFloat((rgb & 0x0000FF00) >>  8) / 255,
                    alpha: CGFloat( rgb & 0x000000FF)         / 255
                )
            default:
                return nil
            }
            return
        }

        // Named SVG/CSS colours
        if let hex = NSColor.svgNamedColors[s] {
            self.init(hex6: hex)
            return
        }

        return nil
    }

    // Legacy hex-only initialiser (kept for backward compatibility)
    convenience init?(hex: String) {
        self.init(svgString: hex)
    }

    // MARK: Private helpers

    private convenience init?(hex6: String, alpha: CGFloat = 1) {
        var rgb: UInt64 = 0
        guard Scanner(string: hex6).scanHexInt64(&rgb), hex6.count == 6 else { return nil }
        self.init(
            red:   CGFloat((rgb & 0xFF0000) >> 16) / 255,
            green: CGFloat((rgb & 0x00FF00) >>  8) / 255,
            blue:  CGFloat( rgb & 0x0000FF)         / 255,
            alpha: alpha
        )
    }

    // MARK: SVG 1.1 full named colour table (147 colours)
    private static let svgNamedColors: [String: String] = [
        "aliceblue": "F0F8FF", "antiquewhite": "FAEBD7", "aqua": "00FFFF",
        "aquamarine": "7FFFD4", "azure": "F0FFFF", "beige": "F5F5DC",
        "bisque": "FFE4C4", "black": "000000", "blanchedalmond": "FFEBCD",
        "blue": "0000FF", "blueviolet": "8A2BE2", "brown": "A52A2A",
        "burlywood": "DEB887", "cadetblue": "5F9EA0", "chartreuse": "7FFF00",
        "chocolate": "D2691E", "coral": "FF7F50", "cornflowerblue": "6495ED",
        "cornsilk": "FFF8DC", "crimson": "DC143C", "cyan": "00FFFF",
        "darkblue": "00008B", "darkcyan": "008B8B", "darkgoldenrod": "B8860B",
        "darkgray": "A9A9A9", "darkgreen": "006400", "darkgrey": "A9A9A9",
        "darkkhaki": "BDB76B", "darkmagenta": "8B008B", "darkolivegreen": "556B2F",
        "darkorange": "FF8C00", "darkorchid": "9932CC", "darkred": "8B0000",
        "darksalmon": "E9967A", "darkseagreen": "8FBC8F", "darkslateblue": "483D8B",
        "darkslategray": "2F4F4F", "darkslategrey": "2F4F4F", "darkturquoise": "00CED1",
        "darkviolet": "9400D3", "deeppink": "FF1493", "deepskyblue": "00BFFF",
        "dimgray": "696969", "dimgrey": "696969", "dodgerblue": "1E90FF",
        "firebrick": "B22222", "floralwhite": "FFFAF0", "forestgreen": "228B22",
        "fuchsia": "FF00FF", "gainsboro": "DCDCDC", "ghostwhite": "F8F8FF",
        "gold": "FFD700", "goldenrod": "DAA520", "gray": "808080",
        "green": "008000", "greenyellow": "ADFF2F", "grey": "808080",
        "honeydew": "F0FFF0", "hotpink": "FF69B4", "indianred": "CD5C5C",
        "indigo": "4B0082", "ivory": "FFFFF0", "khaki": "F0E68C",
        "lavender": "E6E6FA", "lavenderblush": "FFF0F5", "lawngreen": "7CFC00",
        "lemonchiffon": "FFFACD", "lightblue": "ADD8E6", "lightcoral": "F08080",
        "lightcyan": "E0FFFF", "lightgoldenrodyellow": "FAFAD2", "lightgray": "D3D3D3",
        "lightgreen": "90EE90", "lightgrey": "D3D3D3", "lightpink": "FFB6C1",
        "lightsalmon": "FFA07A", "lightseagreen": "20B2AA", "lightskyblue": "87CEFA",
        "lightslategray": "778899", "lightslategrey": "778899", "lightsteelblue": "B0C4DE",
        "lightyellow": "FFFFE0", "lime": "00FF00", "limegreen": "32CD32",
        "linen": "FAF0E6", "magenta": "FF00FF", "maroon": "800000",
        "mediumaquamarine": "66CDAA", "mediumblue": "0000CD", "mediumorchid": "BA55D3",
        "mediumpurple": "9370DB", "mediumseagreen": "3CB371", "mediumslateblue": "7B68EE",
        "mediumspringgreen": "00FA9A", "mediumturquoise": "48D1CC", "mediumvioletred": "C71585",
        "midnightblue": "191970", "mintcream": "F5FFFA", "mistyrose": "FFE4E1",
        "moccasin": "FFE4B5", "navajowhite": "FFDEAD", "navy": "000080",
        "oldlace": "FDF5E6", "olive": "808000", "olivedrab": "6B8E23",
        "orange": "FFA500", "orangered": "FF4500", "orchid": "DA70D6",
        "palegoldenrod": "EEE8AA", "palegreen": "98FB98", "paleturquoise": "AFEEEE",
        "palevioletred": "DB7093", "papayawhip": "FFEFDF", "peachpuff": "FFDAB9",
        "peru": "CD853F", "pink": "FFC0CB", "plum": "DDA0DD",
        "powderblue": "B0E0E6", "purple": "800080", "red": "FF0000",
        "rosybrown": "BC8F8F", "royalblue": "4169E1", "saddlebrown": "8B4513",
        "salmon": "FA8072", "sandybrown": "F4A460", "seagreen": "2E8B57",
        "seashell": "FFF5EE", "sienna": "A0522D", "silver": "C0C0C0",
        "skyblue": "87CEEB", "slateblue": "6A5ACD", "slategray": "708090",
        "slategrey": "708090", "snow": "FFFAFA", "springgreen": "00FF7F",
        "steelblue": "4682B4", "tan": "D2B48C", "teal": "008080",
        "thistle": "D8BFD8", "tomato": "FF6347", "turquoise": "40E0D0",
        "violet": "EE82EE", "wheat": "F5DEB3", "white": "FFFFFF",
        "whitesmoke": "F5F5F5", "yellow": "FFFF00", "yellowgreen": "9ACD32",
    ]
}
