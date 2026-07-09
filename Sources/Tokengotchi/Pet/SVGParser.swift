import AppKit
import Foundation

// MARK: - SVG Data Model

/// How a shape is painted (fill or stroke).
enum SVGPaint: Equatable {
    case color(String)     // hex / named / var(--key) / "none" / "currentColor"
    case gradient(String)  // url(#<id>)

    /// Parse a raw SVG paint value. Returns nil when the value is absent (meaning inherit).
    static func parse(_ value: String?) -> SVGPaint? {
        guard let s = value?.trimmingCharacters(in: .whitespaces), !s.isEmpty else { return nil }
        if s.hasPrefix("url(#") && s.hasSuffix(")") {
            return .gradient(String(s.dropFirst(5).dropLast(1)))
        }
        return .color(s)
    }

    static let none: SVGPaint  = .color("none")
    static let black: SVGPaint = .color("#000000")

    var isNone: Bool {
        if case .color(let s) = self { return s == "none" }
        return false
    }
}

// MARK: Gradient Support

/// A single colour stop in a gradient.
struct SVGGradientStop {
    let offset: CGFloat    // 0.0 – 1.0
    let color: String      // hex / named / var(--key)
    let opacity: CGFloat   // 0.0 – 1.0 (from stop-opacity)
}

/// A parsed gradient defined in `<defs>`.
enum SVGGradientDef {
    case linear(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat,
                stops: [SVGGradientStop], userSpaceOnUse: Bool)
    case radial(cx: CGFloat, cy: CGFloat, r: CGFloat,
                fx: CGFloat, fy: CGFloat,
                stops: [SVGGradientStop], userSpaceOnUse: Bool)
}

/// All reusable definitions collected from the `<defs>` block.
struct SVGDefinitions {
    var gradients: [String: SVGGradientDef] = [:]
    var clipPaths: [String: [CGPath]] = [:]
}

// MARK: Element + Layer

/// A single renderable element (path, circle, ellipse, rect, etc.) in the layer tree.
struct SVGElement {
    let path: CGPath
    // Fill
    let fill: SVGPaint
    let fillOpacity: CGFloat
    let fillRule: CGPathFillRule    // .winding | .evenOdd
    // Stroke
    let stroke: SVGPaint
    let strokeWidth: CGFloat
    let strokeOpacity: CGFloat
    let strokeLinecap: CGLineCap
    let strokeLinejoin: CGLineJoin
    let strokeMiterLimit: CGFloat
    let strokeDashArray: [CGFloat]
    let strokeDashOffset: CGFloat
    // Compositing
    let opacity: CGFloat            // element-level (applied to fill + stroke together)
    let clipPathId: String?
}

/// A named group of elements forming the animation layer tree.
struct SVGLayer {
    let id: String
    var elements: [SVGElement]
    var children: [SVGLayer]
    var opacity: CGFloat            // group-level opacity

    var allPaths: [CGPath] {
        elements.map { $0.path } + children.flatMap { $0.allPaths }
    }
}

/// Top-level result returned by `SVGParser.parseSVG`.
struct SVGDocument {
    let root: SVGLayer
    let defs: SVGDefinitions
}

// MARK: - Parser

enum SVGParser {

    struct ParseError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Public API

    /// Parse an SVG string into an `SVGDocument` (layer tree + definitions).
    static func parseSVG(_ svgString: String) throws -> SVGDocument {
        var clean = svgString
        if !clean.contains("xmlns=") {
            clean = clean.replacingOccurrences(of: "<svg", with: "<svg xmlns=\"http://www.w3.org/2000/svg\"")
        }
        guard let data = clean.data(using: .utf8) else {
            throw ParseError(message: "Invalid SVG text encoding")
        }
        let xmlParser = XMLParser(data: data)
        let delegate  = SVGXMLDelegate()
        xmlParser.delegate = delegate
        guard xmlParser.parse() else {
            throw ParseError(message: "SVG XML parse error: \(xmlParser.parserError?.localizedDescription ?? "unknown")")
        }
        guard let root = delegate.rootLayer else {
            throw ParseError(message: "No root SVG element found.")
        }
        return SVGDocument(root: root, defs: delegate.defs)
    }

    // MARK: Bounding Box

    static func boundingBox(of layer: SVGLayer) -> CGRect {
        boundingBox(of: layer.allPaths)
    }

    static func boundingBox(of paths: [CGPath]) -> CGRect {
        paths.reduce(.null) { $0.union($1.boundingBoxOfPath) }
    }

    // MARK: Scale to Fit

    static func scaleLayer(_ layer: SVGLayer,
                           toFit rect: CGRect,
                           padding: CGFloat = 2) -> (layer: SVGLayer, scale: CGFloat) {
        let bb = boundingBox(of: layer)
        guard bb.width > 0, bb.height > 0 else { return (layer, 1.0) }
        let tr = rect.insetBy(dx: padding, dy: padding)
        let s  = min(tr.width / bb.width, tr.height / bb.height)
        guard s.isFinite, s > 0 else { return (layer, 1.0) }
        var t = CGAffineTransform.identity
            .translatedBy(x: tr.midX, y: tr.midY)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -bb.midX, y: -bb.midY)
        return (scaleLayer(layer, transform: &t), s)
    }

    private static func scaleLayer(_ layer: SVGLayer,
                                   transform: inout CGAffineTransform) -> SVGLayer {
        let scaledElements = layer.elements.compactMap { el -> SVGElement? in
            guard let copy = el.path.copy(using: &transform) else { return nil }
            let sx = abs(transform.a)
            return SVGElement(
                path: copy,
                fill: el.fill,
                fillOpacity: el.fillOpacity,
                fillRule: el.fillRule,
                stroke: el.stroke,
                strokeWidth: el.strokeWidth * sx,
                strokeOpacity: el.strokeOpacity,
                strokeLinecap: el.strokeLinecap,
                strokeLinejoin: el.strokeLinejoin,
                strokeMiterLimit: el.strokeMiterLimit,
                strokeDashArray: el.strokeDashArray.map { $0 * sx },
                strokeDashOffset: el.strokeDashOffset * sx,
                opacity: el.opacity,
                clipPathId: el.clipPathId
            )
        }
        let scaledChildren = layer.children.map { scaleLayer($0, transform: &transform) }
        return SVGLayer(id: layer.id, elements: scaledElements, children: scaledChildren, opacity: layer.opacity)
    }

    // MARK: Transform Parser

    /// Parse an SVG `transform` attribute string into a `CGAffineTransform`.
    /// Supports: translate, scale, rotate, matrix, skewX, skewY.
    /// Multiple transforms are applied left-to-right (as SVG specifies).
    static func parseTransform(_ s: String) -> CGAffineTransform {
        var result    = CGAffineTransform.identity
        var remaining = s.trimmingCharacters(in: .whitespaces)

        while !remaining.isEmpty {
            guard let openIdx  = remaining.firstIndex(of: "("),
                  let closeIdx = remaining.firstIndex(of: ")") else { break }

            let funcName = remaining[remaining.startIndex..<openIdx]
                .trimmingCharacters(in: .whitespaces).lowercased()
            let argsStr  = remaining[remaining.index(after: openIdx)..<closeIdx]
            let args     = argsStr
                .components(separatedBy: CharacterSet(charactersIn: " ,\t\n\r"))
                .compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                .map { CGFloat($0) }

            let t: CGAffineTransform
            switch funcName {
            case "translate":
                t = CGAffineTransform(translationX: args[safe: 0] ?? 0,
                                      y:            args[safe: 1] ?? 0)
            case "scale":
                let sx = args[safe: 0] ?? 1
                t = CGAffineTransform(scaleX: sx, y: args[safe: 1] ?? sx)
            case "rotate":
                let deg = args[safe: 0] ?? 0
                let rad = deg * .pi / 180
                if args.count >= 3 {
                    let cx = args[1], cy = args[2]
                    t = CGAffineTransform(translationX: cx, y: cy)
                        .rotated(by: rad)
                        .translatedBy(x: -cx, y: -cy)
                } else {
                    t = CGAffineTransform(rotationAngle: rad)
                }
            case "matrix":
                t = args.count >= 6
                    ? CGAffineTransform(a: args[0], b: args[1], c: args[2],
                                        d: args[3], tx: args[4], ty: args[5])
                    : .identity
            case "skewx":
                let a = (args[safe: 0] ?? 0) * .pi / 180
                t = CGAffineTransform(a: 1, b: 0, c: tan(a), d: 1, tx: 0, ty: 0)
            case "skewy":
                let a = (args[safe: 0] ?? 0) * .pi / 180
                t = CGAffineTransform(a: 1, b: tan(a), c: 0, d: 1, tx: 0, ty: 0)
            default:
                t = .identity
            }

            result    = result.concatenating(t)
            remaining = String(remaining[remaining.index(after: closeIdx)...])
                .trimmingCharacters(in: .whitespaces)
        }
        return result
    }

    // MARK: CGPath → NSBezierPath helper (unchanged)

    static func appendCGPath(_ cgPath: CGPath, to bezier: NSBezierPath) {
        var lastPoint = CGPoint.zero
        cgPath.applyWithBlock { ptr in
            let el  = ptr.pointee
            let pts = el.points
            switch el.type {
            case .moveToPoint:
                bezier.move(to: pts[0])
                lastPoint = pts[0]
            case .addLineToPoint:
                bezier.line(to: pts[0])
                lastPoint = pts[0]
            case .addQuadCurveToPoint:
                bezier.curve(to: pts[1], controlPoint1: pts[0], controlPoint2: pts[0])
                lastPoint = pts[1]
            case .addCurveToPoint:
                bezier.curve(to: pts[2], controlPoint1: pts[0], controlPoint2: pts[1])
                lastPoint = pts[2]
            case .closeSubpath:
                bezier.close()
                bezier.move(to: lastPoint)
            @unknown default:
                break
            }
        }
    }
}

// MARK: - XML Delegate

private class SVGXMLDelegate: NSObject, XMLParserDelegate {

    // MARK: Inherited presentation state

    struct PresentationStyle {
        var fill: SVGPaint           = .black
        var fillOpacity: CGFloat     = 1.0
        var fillRule: CGPathFillRule = .winding
        var stroke: SVGPaint         = .none
        var strokeWidth: CGFloat     = 1.0
        var strokeOpacity: CGFloat   = 1.0
        var strokeLinecap: CGLineCap       = .butt
        var strokeLinejoin: CGLineJoin     = .miter
        var strokeMiterLimit: CGFloat      = 4.0
        var strokeDashArray: [CGFloat]     = []
        var strokeDashOffset: CGFloat      = 0.0
    }

    // MARK: Group frame on the parse stack

    struct GroupFrame {
        var id: String
        var elements: [SVGElement]           = []
        var children: [SVGLayer]             = []
        var style: PresentationStyle
        var opacity: CGFloat                 = 1.0
        var clipPathId: String?              = nil
        var cumulativeTransform: CGAffineTransform = .identity
    }

    // MARK: State

    private var stack: [GroupFrame] = []
    var rootLayer: SVGLayer?
    var defs = SVGDefinitions()

    // Defs collection
    private var inDefs       = false
    private var defsDepth    = 0   // nesting depth inside <defs>

    // Gradient
    private var currentGradId:      String?               = nil
    private var currentGradLinear:  Bool                  = true
    private var currentGradAttrs:   [String: String]      = [:]
    private var currentGradStops:   [SVGGradientStop]     = []

    // ClipPath
    private var inClipPath:         Bool                  = false
    private var currentClipId:      String?               = nil
    private var currentClipPaths:   [CGPath]              = []

    // MARK: - XMLParserDelegate

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName _: String?,
                attributes attrs: [String: String] = [:]) {

        let name = elementName.lowercased()

        // ── DEFS ──────────────────────────────────────────────────────────────
        if name == "defs" {
            inDefs = true
            defsDepth = 1
            return
        }
        if inDefs && !inClipPath {
            defsDepth += 1

            if name == "lineargradient" || name == "radialgradient" {
                currentGradId     = attrs["id"]
                currentGradLinear = (name == "lineargradient")
                currentGradAttrs  = attrs
                currentGradStops  = []
                return
            }
            if name == "stop" {
                currentGradStops.append(parseStop(attrs: attrs))
                return
            }
            if name == "clippath" {
                inClipPath     = true
                currentClipId  = attrs["id"]
                currentClipPaths = []
                return
            }
            // Anything else inside defs (symbols, etc.) — collect path shapes for clip if needed
            return
        }

        // ── PATHS INSIDE CLIPPATH ─────────────────────────────────────────────
        if inClipPath {
            if let p = buildPath(name: name, attrs: attrs, transform: .identity) {
                currentClipPaths.append(p)
            }
            return
        }

        // ── SVG ROOT ─────────────────────────────────────────────────────────
        if name == "svg" {
            let xform = attrs["transform"].map { SVGParser.parseTransform($0) } ?? .identity
            var frame = GroupFrame(id: attrs["id"] ?? "root", style: PresentationStyle())
            frame.opacity              = parseOpacity(attrs)
            frame.cumulativeTransform  = xform
            frame.clipPathId           = parseClipPathId(attrs)
            stack.append(frame)
            return
        }

        // ── GROUP ────────────────────────────────────────────────────────────
        if name == "g" {
            guard !stack.isEmpty else { return }
            let parent   = stack.last!
            let xform    = attrs["transform"].map { SVGParser.parseTransform($0) } ?? .identity
            var frame    = GroupFrame(
                id: attrs["id"] ?? UUID().uuidString,
                style: resolveStyle(attrs: attrs, inherited: parent.style)
            )
            frame.opacity              = parseOpacity(attrs)
            frame.cumulativeTransform  = parent.cumulativeTransform.concatenating(xform)
            frame.clipPathId           = parseClipPathId(attrs)
            stack.append(frame)
            return
        }

        // ── USE ───────────────────────────────────────────────────────────────
        // <use> is intentionally not supported in the current spec version.
        if name == "use" { return }

        // ── DRAWABLE ELEMENTS ─────────────────────────────────────────────────
        guard !stack.isEmpty else { return }
        let parent = stack.last!

        let elemXform = attrs["transform"].map { SVGParser.parseTransform($0) } ?? .identity
        let totalXform = parent.cumulativeTransform.concatenating(elemXform)

        guard let rawPath = buildPath(name: name, attrs: attrs, transform: totalXform) else { return }

        let style  = resolveStyle(attrs: attrs, inherited: parent.style)
        let el = SVGElement(
            path:             rawPath,
            fill:             style.fill,
            fillOpacity:      style.fillOpacity,
            fillRule:         style.fillRule,
            stroke:           style.stroke,
            strokeWidth:      style.strokeWidth,
            strokeOpacity:    style.strokeOpacity,
            strokeLinecap:    style.strokeLinecap,
            strokeLinejoin:   style.strokeLinejoin,
            strokeMiterLimit: style.strokeMiterLimit,
            strokeDashArray:  style.strokeDashArray,
            strokeDashOffset: style.strokeDashOffset,
            opacity:          parseOpacity(attrs),
            clipPathId:       parseClipPathId(attrs)
        )
        stack[stack.count - 1].elements.append(el)
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName _: String?) {
        let name = elementName.lowercased()

        // ── DEFS ──────────────────────────────────────────────────────────────
        if name == "defs" {
            inDefs    = false
            defsDepth = 0
            return
        }

        if inDefs {
            defsDepth -= 1

            if name == "lineargradient" || name == "radialgradient" {
                finaliseGradient()
                return
            }
            if name == "clippath" {
                finaliseClipPath()
                return
            }
            return
        }

        // ── SVG / GROUP ───────────────────────────────────────────────────────
        if name == "svg" || name == "g" {
            if stack.count > 1 {
                let popped = stack.removeLast()
                let layer  = SVGLayer(id: popped.id, elements: popped.elements,
                                      children: popped.children, opacity: popped.opacity)
                stack[stack.count - 1].children.append(layer)
            } else if stack.count == 1 {
                let popped = stack.removeLast()
                rootLayer  = SVGLayer(id: popped.id, elements: popped.elements,
                                      children: popped.children, opacity: popped.opacity)
            }
        }
    }

    // MARK: - Path Builder

    /// Build a CGPath from element name + attributes, pre-applying the cumulative transform.
    private func buildPath(name: String, attrs: [String: String],
                           transform: CGAffineTransform) -> CGPath? {
        var path: CGPath?

        switch name {
        case "path":
            if let d = attrs["d"] { path = try? SVGPathDecoder.decode(d) }

        case "circle":
            if let cx = cg(attrs["cx"]), let cy = cg(attrs["cy"]), let r = cg(attrs["r"]) {
                path = CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2),
                              transform: nil)
            }

        case "ellipse":
            if let cx = cg(attrs["cx"]), let cy = cg(attrs["cy"]),
               let rx = cg(attrs["rx"]), let ry = cg(attrs["ry"]) {
                path = CGPath(ellipseIn: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2),
                              transform: nil)
            }

        case "rect":
            if let x = cg(attrs["x"] ?? "0"), let y = cg(attrs["y"] ?? "0"),
               let w = cg(attrs["width"]), let h = cg(attrs["height"]) {
                let rx = min(cg(attrs["rx"]) ?? 0, w / 2)
                let ry = min(cg(attrs["ry"]) ?? rx, h / 2)
                let rect = CGRect(x: x, y: y, width: w, height: h)
                if rx > 0 || ry > 0 {
                    path = CGPath(roundedRect: rect, cornerWidth: rx, cornerHeight: ry, transform: nil)
                } else {
                    path = CGPath(rect: rect, transform: nil)
                }
            }

        case "line":
            if let x1 = cg(attrs["x1"]), let y1 = cg(attrs["y1"]),
               let x2 = cg(attrs["x2"]), let y2 = cg(attrs["y2"]) {
                let p = CGMutablePath()
                p.move(to: CGPoint(x: x1, y: y1))
                p.addLine(to: CGPoint(x: x2, y: y2))
                path = p
            }

        case "polyline", "polygon":
            if let pts = attrs["points"] {
                let nums = pts
                    .components(separatedBy: CharacterSet(charactersIn: " ,\t\n\r"))
                    .compactMap { Double($0) }.map { CGFloat($0) }
                if nums.count >= 4, nums.count % 2 == 0 {
                    let p = CGMutablePath()
                    p.move(to: CGPoint(x: nums[0], y: nums[1]))
                    for i in stride(from: 2, to: nums.count, by: 2) {
                        p.addLine(to: CGPoint(x: nums[i], y: nums[i + 1]))
                    }
                    if name == "polygon" { p.closeSubpath() }
                    path = p
                }
            }

        default:
            break
        }

        // Apply cumulative transform
        if let p = path, !transform.isIdentity {
            var t = transform
            return p.copy(using: &t) ?? p
        }
        return path
    }

    // MARK: - Style Resolution

    /// Build a resolved `PresentationStyle` by merging element attributes over the inherited parent style.
    private func resolveStyle(attrs: [String: String],
                              inherited: PresentationStyle) -> PresentationStyle {
        var s = inherited

        // Inline style="" overrides presentation attributes
        let inline = parseInlineCSS(attrs["style"] ?? "")
        func val(_ key: String) -> String? { inline[key] ?? attrs[key] }

        // Fill
        if let v = val("fill")         { s.fill        = SVGPaint.parse(v) ?? s.fill }
        if let v = val("fill-opacity") { s.fillOpacity = cg(v) ?? s.fillOpacity }
        if let v = val("fill-rule")    { s.fillRule     = v == "evenodd" ? .evenOdd : .winding }

        // Stroke
        if let v = val("stroke")         { s.stroke        = SVGPaint.parse(v) ?? s.stroke }
        if let v = val("stroke-width")   { s.strokeWidth   = cg(v) ?? s.strokeWidth }
        if let v = val("stroke-opacity") { s.strokeOpacity = cg(v) ?? s.strokeOpacity }
        if let v = val("stroke-linecap") {
            switch v {
            case "round":  s.strokeLinecap = .round
            case "square": s.strokeLinecap = .square
            default:       s.strokeLinecap = .butt
            }
        }
        if let v = val("stroke-linejoin") {
            switch v {
            case "round": s.strokeLinejoin = .round
            case "bevel": s.strokeLinejoin = .bevel
            default:      s.strokeLinejoin = .miter
            }
        }
        if let v = val("stroke-miterlimit") { s.strokeMiterLimit = cg(v) ?? 4 }
        if let v = val("stroke-dasharray")  {
            if v == "none" {
                s.strokeDashArray = []
            } else {
                s.strokeDashArray = v
                    .components(separatedBy: CharacterSet(charactersIn: " ,"))
                    .compactMap { cg($0) }
            }
        }
        if let v = val("stroke-dashoffset") { s.strokeDashOffset = cg(v) ?? 0 }

        return s
    }

    // MARK: - Helpers

    /// Parse a `stop` element into an SVGGradientStop.
    private func parseStop(attrs: [String: String]) -> SVGGradientStop {
        let inline = parseInlineCSS(attrs["style"] ?? "")

        let offsetStr = attrs["offset"] ?? "0"
        var offset: CGFloat = 0
        if offsetStr.hasSuffix("%") {
            offset = (cg(String(offsetStr.dropLast())) ?? 0) / 100
        } else {
            offset = cg(offsetStr) ?? 0
        }

        let color   = inline["stop-color"]   ?? attrs["stop-color"]   ?? "#000000"
        let opacity = inline["stop-opacity"] ?? attrs["stop-opacity"] ?? "1"
        return SVGGradientStop(offset: offset, color: color, opacity: cg(opacity) ?? 1)
    }

    /// Finalise and store the current gradient definition.
    private func finaliseGradient() {
        guard let id = currentGradId else { return }
        let stops     = currentGradStops
        let userSpace = currentGradAttrs["gradientUnits"] == "userSpaceOnUse"

        if currentGradLinear {
            let x1 = cg(currentGradAttrs["x1"]) ?? 0
            let y1 = cg(currentGradAttrs["y1"]) ?? 0
            let x2 = cg(currentGradAttrs["x2"]) ?? 1
            let y2 = cg(currentGradAttrs["y2"]) ?? 0
            defs.gradients[id] = .linear(x1: x1, y1: y1, x2: x2, y2: y2,
                                          stops: stops, userSpaceOnUse: userSpace)
        } else {
            let cx = cg(currentGradAttrs["cx"]) ?? 0.5
            let cy = cg(currentGradAttrs["cy"]) ?? 0.5
            let r  = cg(currentGradAttrs["r"])  ?? 0.5
            let fx = cg(currentGradAttrs["fx"]) ?? cx
            let fy = cg(currentGradAttrs["fy"]) ?? cy
            defs.gradients[id] = .radial(cx: cx, cy: cy, r: r, fx: fx, fy: fy,
                                          stops: stops, userSpaceOnUse: userSpace)
        }
        currentGradId = nil
    }

    /// Finalise and store the current clipPath definition.
    private func finaliseClipPath() {
        if let id = currentClipId, !currentClipPaths.isEmpty {
            defs.clipPaths[id] = currentClipPaths
        }
        inClipPath = false
        currentClipId = nil
    }

    /// Parse `style="k:v; k:v"` into a dictionary.
    private func parseInlineCSS(_ s: String) -> [String: String] {
        var result: [String: String] = [:]
        for part in s.components(separatedBy: ";") {
            let kv = part.components(separatedBy: ":").map { $0.trimmingCharacters(in: .whitespaces) }
            if kv.count >= 2, !kv[0].isEmpty {
                result[kv[0]] = kv[1...].joined(separator: ":")
            }
        }
        return result
    }

    /// Extract element-level opacity (does NOT cascade in SVG).
    private func parseOpacity(_ attrs: [String: String]) -> CGFloat {
        let inline = parseInlineCSS(attrs["style"] ?? "")
        let s = inline["opacity"] ?? attrs["opacity"] ?? "1"
        return cg(s) ?? 1.0
    }

    /// Extract `clip-path="url(#id)"` → id string.
    private func parseClipPathId(_ attrs: [String: String]) -> String? {
        let inline = parseInlineCSS(attrs["style"] ?? "")
        let s = inline["clip-path"] ?? attrs["clip-path"] ?? ""
        if s.hasPrefix("url(#") && s.hasSuffix(")") {
            return String(s.dropFirst(5).dropLast(1))
        }
        return nil
    }

    /// Safe Double → CGFloat conversion.
    @inline(__always)
    private func cg(_ s: String?) -> CGFloat? {
        guard let s = s?.trimmingCharacters(in: .whitespaces),
              let v = Double(s) else { return nil }
        return CGFloat(v)
    }
}

// MARK: - Path Decoder (unchanged from original)

private enum SVGPathDecoder {

    enum PathCommand {
        case moveTo(CGPoint)
        case lineTo(CGPoint)
        case curveTo(control1: CGPoint, control2: CGPoint, to: CGPoint)
        case quadCurveTo(control: CGPoint, to: CGPoint)
        case closePath
    }

    static func decode(_ d: String) throws -> CGPath {
        let path = CGMutablePath()
        for cmd in parsePathData(d) {
            switch cmd {
            case .moveTo(let pt):                  path.move(to: pt)
            case .lineTo(let pt):                  path.addLine(to: pt)
            case .curveTo(let c1, let c2, let to): path.addCurve(to: to, control1: c1, control2: c2)
            case .quadCurveTo(let c, let to):      path.addQuadCurve(to: to, control: c)
            case .closePath:                       path.closeSubpath()
            }
        }
        return path
    }

    static func parsePathData(_ d: String) -> [PathCommand] {
        var commands: [PathCommand] = []
        var current: CGPoint = .zero
        var subpathStart: CGPoint = .zero
        var lastCmd: String? = nil
        var lastControl: CGPoint? = nil  // for S and T smooth curves

        let tokens = tokenize(d)
        var i = 0

        while i < tokens.count {
            var token = tokens[i]
            i += 1

            if Double(token) != nil, let prev = lastCmd {
                token = prev
                i -= 1
            }

            let isRel = token.first?.isLowercase ?? false
            let cmd   = token.uppercased()
            lastCmd   = token

            switch cmd {
            case "M":
                let pt = parsePoint(tokens: tokens, idx: &i, rel: isRel, cur: current)
                current = pt; subpathStart = pt
                commands.append(.moveTo(pt))
                lastControl = nil
                while i < tokens.count, canBeNumber(tokens[i]) {
                    let pt2 = parsePoint(tokens: tokens, idx: &i, rel: isRel, cur: current)
                    current = pt2
                    commands.append(.lineTo(pt2))
                }
            case "L":
                let pt = parsePoint(tokens: tokens, idx: &i, rel: isRel, cur: current)
                current = pt; commands.append(.lineTo(pt)); lastControl = nil
            case "H":
                let v  = parseNumber(tokens: tokens, idx: &i)
                let pt = isRel ? CGPoint(x: current.x + v, y: current.y) : CGPoint(x: v, y: current.y)
                current = pt; commands.append(.lineTo(pt)); lastControl = nil
            case "V":
                let v  = parseNumber(tokens: tokens, idx: &i)
                let pt = isRel ? CGPoint(x: current.x, y: current.y + v) : CGPoint(x: current.x, y: v)
                current = pt; commands.append(.lineTo(pt)); lastControl = nil
            case "C":
                let c1 = parsePoint(tokens: tokens, idx: &i, rel: isRel, cur: current)
                let c2 = parsePoint(tokens: tokens, idx: &i, rel: isRel, cur: current)
                let to = parsePoint(tokens: tokens, idx: &i, rel: isRel, cur: current)
                commands.append(.curveTo(control1: c1, control2: c2, to: to))
                lastControl = c2; current = to
            case "S":
                let c2 = parsePoint(tokens: tokens, idx: &i, rel: isRel, cur: current)
                let to = parsePoint(tokens: tokens, idx: &i, rel: isRel, cur: current)
                let c1: CGPoint
                if let lc = lastControl {
                    c1 = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                } else {
                    c1 = current
                }
                commands.append(.curveTo(control1: c1, control2: c2, to: to))
                lastControl = c2; current = to
            case "Q":
                let c  = parsePoint(tokens: tokens, idx: &i, rel: isRel, cur: current)
                let to = parsePoint(tokens: tokens, idx: &i, rel: isRel, cur: current)
                commands.append(.quadCurveTo(control: c, to: to))
                lastControl = c; current = to
            case "T":
                let to = parsePoint(tokens: tokens, idx: &i, rel: isRel, cur: current)
                let c: CGPoint
                if let lc = lastControl {
                    c = CGPoint(x: 2 * current.x - lc.x, y: 2 * current.y - lc.y)
                } else {
                    c = current
                }
                commands.append(.quadCurveTo(control: c, to: to))
                lastControl = c; current = to
            case "A":
                // Arc — approximate with a line for now; full arc support is complex
                let _ = parseNumber(tokens: tokens, idx: &i) // rx
                let _ = parseNumber(tokens: tokens, idx: &i) // ry
                let _ = parseNumber(tokens: tokens, idx: &i) // x-rotation
                let _ = parseNumber(tokens: tokens, idx: &i) // large-arc-flag
                let _ = parseNumber(tokens: tokens, idx: &i) // sweep-flag
                let to = parsePoint(tokens: tokens, idx: &i, rel: isRel, cur: current)
                commands.append(.lineTo(to))
                current = to; lastControl = nil
            case "Z":
                commands.append(.closePath)
                current = subpathStart; lastControl = nil
            default:
                break
            }
        }
        return commands
    }

    private static func tokenize(_ d: String) -> [String] {
        var tokens: [String] = []
        var cur = ""
        for ch in d {
            if ch.isLetter {
                if !cur.isEmpty { tokens.append(cur); cur = "" }
                tokens.append(String(ch))
            } else if ch == "," || ch.isWhitespace {
                if !cur.isEmpty { tokens.append(cur); cur = "" }
            } else if ch == "-" && !cur.isEmpty && cur != "e" && cur != "E" && !cur.hasSuffix("e") && !cur.hasSuffix("E") {
                tokens.append(cur); cur = "-"
            } else {
                cur.append(ch)
            }
        }
        if !cur.isEmpty { tokens.append(cur) }
        return tokens
    }

    private static func canBeNumber(_ token: String) -> Bool {
        Double(token) != nil || (token.hasPrefix("-") && token.count > 1)
    }

    private static func parseNumber(tokens: [String], idx: inout Int) -> CGFloat {
        guard idx < tokens.count, let v = Double(tokens[idx]) else { idx += 1; return 0 }
        idx += 1
        return CGFloat(v)
    }

    private static func parsePoint(tokens: [String], idx: inout Int,
                                   rel: Bool, cur: CGPoint) -> CGPoint {
        let x = parseNumber(tokens: tokens, idx: &idx)
        let y = parseNumber(tokens: tokens, idx: &idx)
        return rel ? CGPoint(x: cur.x + x, y: cur.y + y) : CGPoint(x: x, y: y)
    }
}

// MARK: - Utilities

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
