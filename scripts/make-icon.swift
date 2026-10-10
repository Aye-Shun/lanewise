// Draws the Lanewise icon and writes Resources/AppIcon.icns and docs/icon.png. Run: swift scripts/make-icon.swift
import SwiftUI
import AppKit

extension Color {
    init(_ hex: UInt32, _ alpha: Double = 1) {
        self.init(.sRGB, red: Double(hex >> 16 & 255) / 255, green: Double(hex >> 8 & 255) / 255,
                  blue: Double(hex & 255) / 255, opacity: alpha)
    }
}

struct Gem: Shape {
    var rightHalf = false
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
        p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
        if !rightHalf { p.addLine(to: CGPoint(x: r.minX, y: r.midY)) }
        p.closeSubpath()
        return p
    }
}

// Everything is laid out in a 1024 design space, then scaled to the pixel size.
struct Icon: View {
    let px: CGFloat
    var small: Bool { px <= 32 }

    let ringRadius: CGFloat = 255
    let headAngle = 45.0   // degrees clockwise from 12 o'clock
    let sweep = 300.0      // arc length in degrees; the gap sits just ahead of the head

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 185, style: .continuous)
        let stroke: CGFloat = small ? 100 : 70
        let capDegrees = Double(stroke / 2 / ringRadius) * 180 / .pi + 1
        let f = sweep / 360, cap = capDegrees / 360
        let head = CGSize(width: ringRadius * sin(headAngle * .pi / 180),
                          height: -ringRadius * cos(headAngle * .pi / 180))
        let gem = CGSize(width: small ? 180 : 150, height: small ? 250 : 210)

        ZStack {
            shape.fill(LinearGradient(colors: [Color(0x1A2B4C), Color(0x070B16)], startPoint: .top, endPoint: .bottom))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 22, y: 10)

            ZStack {
                RadialGradient(colors: [Color(0x2E6BFF, 0.30), Color(0x2E6BFF, 0)],
                               center: .center, startRadius: 0, endRadius: 400)
                if !small {
                    shape.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.10), location: 0),
                                                              .init(color: .white.opacity(0), location: 0.55)],
                                                      startPoint: .top, endPoint: .bottom), lineWidth: 3)
                    Circle().stroke(Color.white.opacity(0.07), lineWidth: 10)
                        .frame(width: ringRadius * 2, height: ringRadius * 2)
                }

                Circle().fill(Color(0x6FD8FF, 0.60)).frame(width: 110, height: 110)
                    .blur(radius: 28).offset(head)

                // Trimmed circles start at 3 o'clock, so rotate the tail to (headAngle - sweep) from 12 o'clock.
                Circle().trim(from: 0, to: f)
                    .stroke(AngularGradient(gradient: Gradient(stops: [
                                .init(color: Color(0x409CFF, 0), location: 0),
                                .init(color: Color(0x409CFF), location: f * 0.55),
                                .init(color: Color(0x6FD8FF), location: f * 0.85),
                                .init(color: Color(0xDFF8FF), location: f),
                                .init(color: Color(0xDFF8FF), location: f + cap),   // keeps the round head cap bright
                                .init(color: Color(0x409CFF, 0), location: f + cap + 1 / 360),
                                .init(color: Color(0x409CFF, 0), location: 1)]),
                                            center: .center, startAngle: .zero, endAngle: .degrees(360)),
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .frame(width: ringRadius * 2, height: ringRadius * 2)
                    .rotationEffect(.degrees(headAngle - sweep - 90))

                Gem().fill(Color(0x5CE1E6, 0.45)).frame(width: gem.width, height: gem.height).blur(radius: 40)
                Gem().fill(Color(0xF2FBFF)).frame(width: gem.width, height: gem.height)
                Gem(rightHalf: true).fill(Color(0x9FD8FF)).frame(width: gem.width, height: gem.height)
            }
            .frame(width: 824, height: 824)
            .clipShape(shape)
        }
        .frame(width: 1024, height: 1024)
        .scaleEffect(px / 1024, anchor: .topLeading)
        .frame(width: px, height: px, alignment: .topLeading)
    }
}

func png(_ px: Int) -> Data {
    MainActor.assumeIsolated {
        let renderer = ImageRenderer(content: Icon(px: CGFloat(px)))
        renderer.scale = 1
        guard let image = renderer.cgImage, image.width == px, image.height == px,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            fatalError("could not render \(px)px icon")
        }
        return data
    }
}

let fm = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: iconset) }

for size in [16, 32, 128, 256, 512] {
    try png(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}

let resources = root.appendingPathComponent("Resources")
try fm.createDirectory(at: resources, withIntermediateDirectories: true)
let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

try png(512).write(to: root.appendingPathComponent("docs/icon.png"))
print("Wrote Resources/AppIcon.icns and docs/icon.png")
