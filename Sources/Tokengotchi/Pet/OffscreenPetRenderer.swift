import AppKit

struct OffscreenPetRenderer {

    /// Render a single frame for the given clip ID.
    static func renderFrame(clipID: String, config: PetConfig, time: TimeInterval, stamina: Double? = nil, modelName: String? = nil) -> NSImage {
        let size = NSSize(width: 22, height: 22)

        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.clear.set()
            rect.fill()

            // cx=11 for all clips (center of 22px canvas)
            let cx: CGFloat = 11.0

            var squish: CGFloat = 0
            var bounce: CGFloat = 0
            var xOffset: CGFloat = 0
            var tilt: CGFloat = 0

            let blobColor = NSColor.black
            let eyeColor = NSColor.black // drawn with .clear

            var eyeBlink = false
            var eyeStyle = "normal" // normal, happy, dead, wide, droopy

            var showSweat = false
            var showDots = false
            var showZzz = false
            var glitchMode = false

            // Decorations toggled per-clip
            var showKeyboard = false
            var showMagnifier = false
            var showGlasses = false
            var showExclamation = false
            var showSweatband = false
            var showSpeedLines = false
            var showFootTap = false
            var showQuestionMark = false
            // Pupil motion selector
            var pupilMotion: PupilMotion = .none

            switch clipID {
            // ──────────── Idle ────────────
            case "idle_breathe":
                let st = stamina ?? 1.0
                if st >= 0.8 {
                    squish = sin(time * 3.0) * 1.0
                    bounce = abs(sin(time * 3.0)) * 1.5
                    eyeBlink = sin(time * 1.5) > 0.95
                    if sin(time * 1.5) > 0.8 { eyeStyle = "happy" }
                } else if st >= 0.6 {
                    squish = sin(time * 3.0) * 0.8
                    bounce = abs(sin(time * 3.0)) * 1.0
                    eyeBlink = sin(time * 1.5) > 0.95
                } else if st >= 0.4 {
                    squish = sin(time * 2.0) * 0.5
                    bounce = abs(sin(time * 2.0)) * 0.5
                    eyeStyle = "droopy"
                } else if st > 0.0 {
                    squish = sin(time * 1.5) * 0.3
                    bounce = abs(sin(time * 1.5)) * 0.2
                    eyeStyle = "droopy"
                    showSweat = true
                } else {
                    squish = -2.0
                    bounce = 0
                    eyeStyle = "dead"
                    showZzz = true
                }

            case "idle_walker":
                xOffset = sin(time * 1.2) * 3.0
                bounce = abs(sin(time * 2.4)) * 1.0
                squish = sin(time * 2.4) * 0.3
                eyeBlink = sin(time * 1.5) > 0.95

            case "idle_yawn":
                squish = -abs(sin(time * 1.5)) * 4.0 // stretches up tall
                bounce = abs(sin(time * 1.5)) * 0.5
                eyeBlink = sin(time * 1.0) > 0.6     // drowsy blinks
                eyeStyle = "droopy"

            case "idle_nap":
                squish = -1.5 + sin(time * 1.0) * 0.3
                bounce = 0
                eyeStyle = "dead"
                showZzz = true

            case "idle_wave":
                // Was "wake" — sunrise stretch + wave
                squish = -abs(sin(time * 4.0)) * 4.0 // stretches up tall
                eyeStyle = "wide"
                // little wave offset on the right side
                xOffset = sin(time * 6.0) * 0.5

            case "idle_lookaround":
                tilt = sin(time * 1.8) * 12.0
                bounce = abs(sin(time * 2.0)) * 0.5
                pupilMotion = .slowScan

            case "idle_stretch":
                squish = -abs(sin(time * 2.0)) * 3.5
                bounce = abs(sin(time * 2.0)) * 0.5
                eyeStyle = "wide"

            // ──────────── Busy: thinking ────────────
            case "busy_think_pace":
                tilt = sin(time * 4.0) * 15.0
                bounce = abs(sin(time * 2.0)) * 1.0
                showDots = true
                pupilMotion = .thinkTwitch

            case "busy_think_ponder":
                tilt = sin(time * 2.0) * 8.0
                bounce = abs(sin(time * 1.5)) * 0.6
                pupilMotion = .slowScan

            // ──────────── Busy: reading ────────────
            case "busy_read_scan":
                bounce = abs(sin(time * 2.5)) * 1.0
                squish = sin(time * 2.5) * 0.3
                showGlasses = true
                pupilMotion = .slowScan

            case "busy_read_deep":
                bounce = abs(sin(time * 1.8)) * 0.6
                squish = sin(time * 1.8) * 0.2
                eyeStyle = "droopy"
                showGlasses = true

            // ──────────── Busy: writing ────────────
            case "busy_write_type":
                bounce = abs(sin(time * 8.0)) * 2.5
                squish = sin(time * 8.0) * 0.5
                eyeStyle = "droopy"
                showKeyboard = true

            case "busy_write_burst":
                bounce = abs(sin(time * 12.0)) * 3.0
                squish = sin(time * 12.0) * 0.8
                eyeStyle = "droopy"
                showKeyboard = true
                showSweat = true

            // ──────────── Busy: searching ────────────
            case "busy_search_lean":
                tilt = sin(time * 3.0) * 10.0
                bounce = abs(sin(time * 3.0)) * 1.0
                showMagnifier = true
                pupilMotion = .slowScan

            case "busy_search_sweep":
                tilt = sin(time * 4.0) * 12.0
                bounce = abs(sin(time * 4.0)) * 1.2
                eyeStyle = "wide"
                showMagnifier = true
                pupilMotion = .slowScan

            // ──────────── Busy: planning ────────────
            case "busy_plan_lightbulb":
                tilt = sin(time * 6.0) * 15.0
                bounce = abs(sin(time * 4.0)) * 1.0
                eyeStyle = "wide"
                showDots = true
                showExclamation = true

            case "busy_plan_dots":
                tilt = sin(time * 5.0) * 12.0
                bounce = abs(sin(time * 3.0)) * 0.8
                eyeStyle = "wide"
                showDots = true

            // ──────────── Busy: building ────────────
            case "busy_build_sweat":
                bounce = abs(sin(time * 10.0)) * 3.0
                squish = sin(time * 10.0) * 1.0
                eyeStyle = "droopy"
                showSweat = true
                showSweatband = true

            // ──────────── Busy: running ────────────
            case "busy_run_dash":
                tilt = -15.0
                bounce = abs(sin(time * 15.0)) * 2.0
                squish = sin(time * 15.0) * 0.5
                eyeStyle = "wide"
                showSweat = true
                showSpeedLines = true

            case "busy_run_sprint":
                tilt = -12.0
                bounce = abs(sin(time * 18.0)) * 2.5
                squish = sin(time * 18.0) * 0.6
                eyeStyle = "wide"
                showSweat = true
                showSpeedLines = true

            // ──────────── Waiting ────────────
            case "waiting_tap":
                squish = 0
                bounce = abs(sin(time * 4.0)) * 0.5
                eyeStyle = "wide"
                showFootTap = true
                showQuestionMark = true

            case "waiting_look":
                squish = sin(time * 2.5) * 0.3
                bounce = abs(sin(time * 2.5)) * 1.0
                eyeStyle = "wide"
                showQuestionMark = true

            case "waiting_blink":
                tilt = sin(time * 1.5) * 8.0
                bounce = abs(sin(time * 1.5)) * 0.4
                eyeBlink = sin(time * 2.0) > 0.3
                showQuestionMark = true

            // ──────────── Completed ────────────
            case "done_jump":
                bounce = abs(sin(time * 6.0)) * 4.0
                if bounce > 2.0 {
                    eyeStyle = "happy"
                } else {
                    squish = -bounce * 0.5
                }

            case "done_spin":
                // Spin = quick tilt rotation + hop
                tilt = (time * 360).truncatingRemainder(dividingBy: 360)
                bounce = abs(sin(time * 8.0)) * 3.5
                if bounce > 2.0 { eyeStyle = "happy" }

            // ──────────── Error ────────────
            case "error_shake":
                glitchMode = true
                eyeStyle = "dead"
                xOffset = sin(time * 30.0) * 1.5
                squish = sin(time * 15.0) * 0.5
                showSweat = true

            case "error_trip":
                tilt = sin(time * 12.0) * 20.0
                xOffset = sin(time * 8.0) * 2.0
                bounce = abs(sin(time * 6.0)) * 1.0
                eyeStyle = "dead"
                showSweat = true

            default:
                // Fallback: gentle breathe
                squish = sin(time * 3.0) * 1.0
                bounce = abs(sin(time * 3.0)) * 1.5
            }

            let baseWidth: CGFloat = 16.0
            let baseHeight: CGFloat = 12.0
            let baseY: CGFloat = 3.0

            let w = baseWidth + squish
            let h = baseHeight - squish
            let y = baseY + bounce

            NSGraphicsContext.current?.saveGraphicsState()

            // Apply tilt (rotate around center of blob)
            let transform = NSAffineTransform()
            transform.translateX(by: cx + xOffset, yBy: y + h/2)
            transform.rotate(byDegrees: tilt)
            transform.translateX(by: -(cx + xOffset), yBy: -(y + h/2))
            transform.concat()

            // Body
            let bodyRect = NSRect(x: cx + xOffset - w/2.0, y: y, width: w, height: h)

            if glitchMode {
                blobColor.set()
                let r1 = NSRect(x: bodyRect.minX - 1, y: bodyRect.minY, width: w + 2, height: h/2)
                let r2 = NSRect(x: bodyRect.minX + 2, y: bodyRect.minY + h/2, width: w - 1, height: h/2)
                NSBezierPath(rect: r1).fill()
                NSBezierPath(rect: r2).fill()
            } else {
                blobColor.set()
                let path = NSBezierPath(roundedRect: bodyRect, xRadius: w/3.0, yRadius: h/3.0)
                path.fill()
            }

            // --- Body Attachments ---

            if showKeyboard {
                NSColor.darkGray.set()
                let kbW: CGFloat = 10
                let kbH: CGFloat = 1.5
                let kbX = cx + xOffset - kbW / 2
                let kbY = y + 1 + bounce * 0.2
                let kbRect = NSRect(x: kbX, y: kbY, width: kbW, height: kbH)
                NSBezierPath(roundedRect: kbRect, xRadius: 0.5, yRadius: 0.5).fill()
            }

            if showMagnifier {
                NSGraphicsContext.current?.saveGraphicsState()
                let magX = cx + xOffset + 5
                let magY = y + 2 + bounce * 0.5
                NSColor.black.set()
                let handle = NSRect(x: magX + 2, y: magY - 4, width: 1.5, height: 6)
                let handlePath = NSBezierPath(roundedRect: handle, xRadius: 0.5, yRadius: 0.5)
                handlePath.fill()

                let glass = NSRect(x: magX - 2, y: magY + 1, width: 6, height: 6)
                let glassPath = NSBezierPath(ovalIn: glass)
                glassPath.lineWidth = 1.5
                glassPath.stroke()
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: glass.insetBy(dx: 1, dy: 1)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSGraphicsContext.current?.restoreGraphicsState()
            }

            if showExclamation {
                let pulse = sin(time * 5.0) > 0 ? 1.0 : 0.5
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12, weight: .bold), .foregroundColor: NSColor.systemYellow.withAlphaComponent(pulse)]
                "!".draw(at: NSPoint(x: cx + 4, y: y + h + 2), withAttributes: attrs)
            }

            if showSweatband {
                NSColor(calibratedRed: 0.9, green: 0.3, blue: 0.3, alpha: 1).set()
                let bandY = y + h - 3.5
                let bandRect = NSRect(x: cx + xOffset - w/2 - 0.5, y: bandY, width: w + 1, height: 2)
                NSBezierPath(rect: bandRect).fill()
                let tailPath = NSBezierPath()
                tailPath.move(to: NSPoint(x: cx + xOffset + w/2, y: bandY + 1))
                tailPath.line(to: NSPoint(x: cx + xOffset + w/2 + 2, y: bandY - 1))
                tailPath.line(to: NSPoint(x: cx + xOffset + w/2 + 3, y: bandY + 2))
                tailPath.lineWidth = 0.8
                tailPath.stroke()
            }

            if showSpeedLines {
                NSColor.black.withAlphaComponent(0.5).set()
                let phase1 = CGFloat(Int(time * 30.0) % 5) / 5.0
                let phase2 = CGFloat(Int(time * 25.0 + 1) % 5) / 5.0
                let phase3 = CGFloat(Int(time * 35.0 + 2) % 5) / 5.0

                let lineX = cx + xOffset - w/2.0 - 2.0
                let line1 = NSRect(x: lineX - 6.0 * phase1 - 4, y: y + 3.0, width: 4.0, height: 1.0)
                let line2 = NSRect(x: lineX - 8.0 * phase2 - 6, y: y + h/2.0, width: 6.0, height: 1.0)
                let line3 = NSRect(x: lineX - 5.0 * phase3 - 2, y: y + h - 3.0, width: 3.0, height: 1.0)

                NSBezierPath(rect: line1).fill()
                NSBezierPath(rect: line2).fill()
                NSBezierPath(rect: line3).fill()
            }

            if showFootTap {
                blobColor.set()
                let footW: CGFloat = 3
                let footH: CGFloat = 1.5
                let footX = cx + xOffset + w/2 - 4
                let tapPhase = sin(time * 20.0)
                let footY = y + (tapPhase > 0 ? tapPhase * 1.5 : 0) - 1.0
                let footRect = NSRect(x: footX, y: footY, width: footW, height: footH)
                NSBezierPath(roundedRect: footRect, xRadius: 0.5, yRadius: 0.5).fill()
            }

            // Eyes
            eyeColor.set()
            let eyeY = y + h * 0.5

            NSGraphicsContext.current?.compositingOperation = .clear

            if eyeBlink {
                let leftEye = NSRect(x: cx + xOffset - 4, y: eyeY, width: 3, height: 1)
                let rightEye = NSRect(x: cx + xOffset + 1, y: eyeY, width: 3, height: 1)
                NSBezierPath(rect: leftEye).fill()
                NSBezierPath(rect: rightEye).fill()
            } else if eyeStyle == "happy" {
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 8, weight: .bold), .foregroundColor: eyeColor]
                "^".draw(at: NSPoint(x: cx + xOffset - 5, y: eyeY - 2), withAttributes: attrs)
                "^".draw(at: NSPoint(x: cx + xOffset + 1, y: eyeY - 2), withAttributes: attrs)
            } else if eyeStyle == "dead" {
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 6, weight: .bold), .foregroundColor: eyeColor]
                "x".draw(at: NSPoint(x: cx + xOffset - 5, y: eyeY - 1), withAttributes: attrs)
                "x".draw(at: NSPoint(x: cx + xOffset + 1, y: eyeY - 1), withAttributes: attrs)
            } else if eyeStyle == "wide" {
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 6, weight: .bold), .foregroundColor: eyeColor]
                "o".draw(at: NSPoint(x: cx + xOffset - 5, y: eyeY - 1), withAttributes: attrs)
                "o".draw(at: NSPoint(x: cx + xOffset + 1, y: eyeY - 1), withAttributes: attrs)
            } else {
                // Normal open eyes with optional pupil motion
                let eyeW: CGFloat = 2.5
                var eyeH: CGFloat = 3.5
                var pupilDir: CGFloat = 0

                switch pupilMotion {
                case .none:
                    break
                case .slowScan:
                    pupilDir = sin(time * 1.5) * 1.5
                case .thinkTwitch:
                    pupilDir = sin(time * 2.0) > 0 ? 1 : -1
                }

                if eyeStyle == "droopy" {
                    eyeH = 1.5
                }

                let leftEye = NSRect(x: cx + xOffset - 4 + pupilDir, y: eyeY, width: eyeW, height: eyeH)
                let rightEye = NSRect(x: cx + xOffset + 1 + pupilDir, y: eyeY, width: eyeW, height: eyeH)
                NSBezierPath(rect: leftEye).fill()
                NSBezierPath(rect: rightEye).fill()
            }

            NSGraphicsContext.current?.compositingOperation = .sourceOver

            // Restore state so decorations don't rotate with the body
            NSGraphicsContext.current?.restoreGraphicsState()

            // Decorations
            if showSweat {
                NSColor.systemCyan.set()
                let dropY = y + h * 0.8 - abs(sin(time * 15.0) * 3.0)
                let drop = NSRect(x: cx + xOffset + 5, y: dropY, width: 2, height: 3)
                NSBezierPath(ovalIn: drop).fill()
            }

            if showDots {
                NSColor.white.set()
                let dotCount = Int(time * 3.0) % 4
                let dots = String(repeating: ".", count: dotCount)
                let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.white]
                dots.draw(at: NSPoint(x: cx - 6, y: y + h - 2), withAttributes: attrs)
            }

            if showZzz {
                NSColor.white.set()
                let zPhase1 = (time * 2.0).truncatingRemainder(dividingBy: 3.0)
                let zPhase2 = (time * 2.0 + 1.0).truncatingRemainder(dividingBy: 3.0)

                let attrs1: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 6, weight: .bold), .foregroundColor: NSColor.white.withAlphaComponent(1.0 - zPhase1/3.0)]
                let attrs2: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 4, weight: .bold), .foregroundColor: NSColor.white.withAlphaComponent(1.0 - zPhase2/3.0)]

                "Z".draw(at: NSPoint(x: cx + 2 + zPhase1 * 2, y: y + h + 2 + zPhase1 * 4), withAttributes: attrs1)
                "z".draw(at: NSPoint(x: cx + 5 + zPhase2 * 2, y: y + h + zPhase2 * 4), withAttributes: attrs2)
            }

            if showGlasses {
                NSColor.black.setStroke()
                let glW: CGFloat = 4.5
                let glH: CGFloat = 3.5
                let glLeft = NSRect(x: cx + xOffset - 4.5, y: eyeY - 0.5, width: glW, height: glH)
                let glRight = NSRect(x: cx + xOffset + 0.5, y: eyeY - 0.5, width: glW, height: glH)

                let lPath = NSBezierPath(rect: glLeft)
                lPath.lineWidth = 0.5
                lPath.stroke()

                let rPath = NSBezierPath(rect: glRight)
                rPath.lineWidth = 0.5
                rPath.stroke()

                let bridge = NSBezierPath()
                bridge.move(to: NSPoint(x: cx + xOffset, y: eyeY + 1.5))
                bridge.line(to: NSPoint(x: cx + xOffset + 0.5, y: eyeY + 1.5))
                bridge.lineWidth = 0.5
                bridge.stroke()
            }

            if showQuestionMark {
                let pulse = sin(time * 6.0) > 0 ? 1.0 : 0.5
                NSColor.systemYellow.withAlphaComponent(pulse).set()
                let qX = cx + 2.0
                let qY = y + h + 2.0

                // Pixel-art "?"
                NSBezierPath(rect: NSRect(x: qX, y: qY + 6, width: 3, height: 1)).fill()
                NSBezierPath(rect: NSRect(x: qX - 1, y: qY + 5, width: 1, height: 1)).fill()
                NSBezierPath(rect: NSRect(x: qX + 3, y: qY + 4, width: 1, height: 2)).fill()
                NSBezierPath(rect: NSRect(x: qX + 2, y: qY + 3, width: 1, height: 1)).fill()
                NSBezierPath(rect: NSRect(x: qX + 1, y: qY + 2, width: 1, height: 1)).fill()
                NSBezierPath(rect: NSRect(x: qX + 1, y: qY, width: 1, height: 1)).fill()
            }

            return true
        }

        image.isTemplate = true
        return image
    }

    // MARK: - Pupil Motion
    private enum PupilMotion {
        case none
        case slowScan
        case thinkTwitch
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else {
            return nil
        }

        let length = hexSanitized.count
        guard length == 6 else {
            return nil
        }

        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}
