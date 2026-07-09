import AppKit

struct VectorPetRenderer {

    static let canvasSize: CGFloat = 128

    enum RenderingContext {
        case main
        case menuBar
    }

    @MainActor
    static func renderStaticIcon(size: CGFloat, context: RenderingContext = .main) -> NSImage {
        let pet = PetManager.defaultPet()
        let targetContext = context == .menuBar ? pet.menuBar : pet.dock
        let firstAnimationId = targetContext.states.first?.animations.first?.id ?? ""

        let sourceImage = renderFrame(
            clipID: firstAnimationId, pet: pet, time: 0, context: context)
        let targetSize = NSSize(width: size, height: size)
        let scaled = NSImage(size: targetSize, flipped: false) { rect in
            sourceImage.draw(in: rect, from: .zero, operation: .copy, fraction: 1.0)
            return true
        }
        scaled.isTemplate = false
        return scaled
    }

    static func renderFrame(
        clipID: String, pet: TGPetFile, time: TimeInterval,
        stamina: Double? = nil, modelName: String? = nil,
        context: RenderingContext = .main
    ) -> NSImage {
        let size  = NSSize(width: canvasSize, height: canvasSize)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.set()
            rect.fill()

            // Flip context: SVG (Y-down) → AppKit (Y-up)
            NSGraphicsContext.current?.saveGraphicsState()
            let flip = NSAffineTransform()
            flip.translateX(by: 0, yBy: size.height)
            flip.scaleX(by: 1, yBy: -1)
            flip.concat()

            // 1. Find the animation entry
            let duration: TimeInterval
            let tracks: [KeyframeTrack]
            let svgString: String

            let targetContext = context == .menuBar ? pet.menuBar : pet.dock

            if let animation = targetContext.findAnimation(id: clipID) {
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
                tracks    = []
            }

            // 2. Parse the SVG
            guard let doc = try? SVGParser.parseSVG(svgString) else { return true }

            // 3. Evaluate keyframe transforms
            let transforms = AnimationEvaluator.evaluate(tracks: tracks, duration: duration, time: time)

            // 4. Scale to fit (with padding)
            let innerRect   = rect.insetBy(dx: 12, dy: 12)
            let scaleResult = SVGParser.scaleLayer(doc.root, toFit: innerRect, padding: 1)
            let scaledLayer = scaleResult.layer

            // 5. Draw
            NSGraphicsContext.current?.saveGraphicsState()
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.setShadow(
                    offset: CGSize(width: 0, height: -3),
                    blur:   6,
                    color:  NSColor.black.withAlphaComponent(0.25).cgColor)
            }

            drawLayer(scaledLayer, transforms: transforms, pet: pet,
                      scale: scaleResult.scale, defs: doc.defs)

            NSGraphicsContext.current?.restoreGraphicsState() // restore shadow
            NSGraphicsContext.current?.restoreGraphicsState() // restore flip

            return true
        }
        image.isTemplate = false
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

        // Apply keyframe animation transform (centred on layer bounding box)
        let bb = SVGParser.boundingBox(of: layer)
        let cx = bb.midX
        let cy = bb.midY
        let animXform = NSAffineTransform()
        animXform.translateX(by: cx + t.tx * scale, yBy: cy + t.ty * scale)
        animXform.rotate(byDegrees: t.rotate)
        animXform.scaleX(by: t.sx, yBy: t.sy)
        animXform.translateX(by: -cx, yBy: -cy)
        animXform.concat()

        // Apply group-level opacity
        if layer.opacity < 1.0, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setAlpha(layer.opacity)
        }

        // Draw elements
        for element in layer.elements {
            drawElement(element, pet: pet, defs: defs)
        }

        // Recurse into child layers
        for child in layer.children {
            drawLayer(child, transforms: transforms, pet: pet, scale: scale, defs: defs)
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // MARK: - Element Rendering

    private static func drawElement(_ element: SVGElement,
                                    pet: TGPetFile,
                                    defs: SVGDefinitions) {
        NSGraphicsContext.current?.saveGraphicsState()
        NSGraphicsContext.current?.compositingOperation = .sourceOver

        // Apply element-level clip-path
        if let clipId = element.clipPathId,
           let clipPaths = defs.clipPaths[clipId],
           let ctx = NSGraphicsContext.current?.cgContext {
            ctx.saveGState()
            for cp in clipPaths { ctx.addPath(cp) }
            ctx.clip()
        }

        // Apply element-level opacity via context alpha
        if element.opacity < 1.0, let ctx = NSGraphicsContext.current?.cgContext {
            ctx.setAlpha(element.opacity)
        }

        // Build bezier path
        let bezier = NSBezierPath()
        SVGParser.appendCGPath(element.path, to: bezier)
        bezier.windingRule    = element.fillRule == .evenOdd ? .evenOdd : .nonZero
        bezier.lineWidth      = element.strokeWidth
        bezier.lineCapStyle   = element.strokeLinecap  == .round  ? .round  :
                                 element.strokeLinecap  == .square ? .square : .butt
        bezier.lineJoinStyle  = element.strokeLinejoin == .round  ? .round  :
                                 element.strokeLinejoin == .bevel  ? .bevel  : .miter
        bezier.miterLimit     = element.strokeMiterLimit

        if !element.strokeDashArray.isEmpty {
            var dashArray = element.strokeDashArray
            bezier.setLineDash(&dashArray,
                               count: dashArray.count,
                               phase: element.strokeDashOffset)
        }

        // MARK: Fill
        switch element.fill {
        case .color(let colorStr):
            if colorStr != "none" {
                let resolved = resolveColorString(colorStr, palette: pet.palette)
                let alpha    = element.fillOpacity  // element.opacity already applied to ctx
                if let color = NSColor(svgString: resolved)?.withAlphaComponent(
                    (NSColor(svgString: resolved)?.alphaComponent ?? 1) * alpha) {
                    color.setFill()
                    bezier.fill()
                }
            }

        case .gradient(let gradId):
            if let gradDef = defs.gradients[gradId],
               let ctx = NSGraphicsContext.current?.cgContext {
                drawGradient(gradDef, bezier: bezier,
                             fillOpacity: element.fillOpacity,
                             palette: pet.palette, ctx: ctx)
            }
        }

        // MARK: Stroke
        switch element.stroke {
        case .color(let colorStr):
            if colorStr != "none" {
                let resolved = resolveColorString(colorStr, palette: pet.palette)
                let alpha    = element.strokeOpacity
                if let color = NSColor(svgString: resolved)?.withAlphaComponent(
                    (NSColor(svgString: resolved)?.alphaComponent ?? 1) * alpha) {
                    color.setStroke()
                    bezier.stroke()
                }
            }

        case .gradient(let gradId):
            // Stroke gradients: stroke-to-fill trick (clip to stroke path then fill gradient)
            if let gradDef = defs.gradients[gradId],
               let ctx = NSGraphicsContext.current?.cgContext {
                let strokePath = bezier.copy() as? NSBezierPath ?? bezier
                strokePath.lineWidth = element.strokeWidth
                ctx.saveGState()
                // Use CGContext to clip to stroke region
                ctx.addPath(strokePath.cgPath)
                ctx.replacePathWithStrokedPath()
                ctx.clip()
                drawGradient(gradDef, bezier: strokePath,
                             fillOpacity: element.strokeOpacity,
                             palette: pet.palette, ctx: ctx)
                ctx.restoreGState()
            }
        }

        NSGraphicsContext.current?.restoreGraphicsState()
    }

    // MARK: - Gradient Rendering

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
            let alpha    = stop.opacity * fillOpacity
            if let base  = NSColor(svgString: resolved) {
                cgColors.append(base.withAlphaComponent(base.alphaComponent * alpha).cgColor)
                locations.append(stop.offset)
            }
        }
        guard !cgColors.isEmpty,
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: cgColors as CFArray,
                                        locations: locations) else { return }

        // Clip to element path, then draw gradient
        ctx.saveGState()
        ctx.addPath(bezier.cgPath)
        ctx.clip()

        let bb = bezier.bounds
        let opts: CGGradientDrawingOptions = [.drawsBeforeStartLocation, .drawsAfterEndLocation]

        switch gradDef {
        case .linear(let x1, let y1, let x2, let y2, _, let userSpace):
            let start: CGPoint
            let end: CGPoint
            if userSpace {
                start = CGPoint(x: x1, y: y1)
                end   = CGPoint(x: x2, y: y2)
            } else {
                start = CGPoint(x: bb.minX + x1 * bb.width,  y: bb.minY + y1 * bb.height)
                end   = CGPoint(x: bb.minX + x2 * bb.width,  y: bb.minY + y2 * bb.height)
            }
            ctx.drawLinearGradient(gradient, start: start, end: end, options: opts)

        case .radial(let cx, let cy, let r, let fx, let fy, _, let userSpace):
            let center: CGPoint
            let focal:  CGPoint
            let radius: CGFloat
            if userSpace {
                center = CGPoint(x: cx, y: cy)
                focal  = CGPoint(x: fx, y: fy)
                radius = r
            } else {
                let scaleX = bb.width, scaleY = bb.height
                center = CGPoint(x: bb.minX + cx * scaleX, y: bb.minY + cy * scaleY)
                focal  = CGPoint(x: bb.minX + fx * scaleX, y: bb.minY + fy * scaleY)
                radius = r * min(scaleX, scaleY)
            }
            ctx.drawRadialGradient(gradient,
                                   startCenter: focal,  startRadius: 0,
                                   endCenter:   center, endRadius:   radius,
                                   options: opts)
        }
        ctx.restoreGState()
    }

    // MARK: - Colour Resolution

    /// Resolve a `var(--key)` paint string to the actual hex value using the palette.
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

// MARK: - NSBezierPath CGPath helper

private extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [CGPoint](repeating: .zero, count: 3)
        for i in 0..<self.elementCount {
            let type = self.element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:             path.move(to: points[0])
            case .lineTo:             path.addLine(to: points[0])
            case .curveTo:            path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .cubicCurveTo:       path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:   path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:          path.closeSubpath()
            @unknown default:         break
            }
        }
        return path
    }
}
