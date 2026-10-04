// Draws the app icon: 1024×1024, opaque, very simple abstract shapes. iOS rounds the corners.
//   swift scripts/make_icon.swift <wall|slash|cube> <output.png>
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let style = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "wall"
let output = URL(fileURLWithPath: CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "AppIcon-1024.png")

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func fill(_ rect: CGRect, _ color: CGColor, radius: CGFloat = 0) {
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.setFillColor(color)
    context.fillPath()
}

func polygon(_ points: [CGPoint], _ color: CGColor) {
    context.addLines(between: points)
    context.closePath()
    context.setFillColor(color)
    context.fillPath()
}

/// Three rows of bricks: a wall that callers can't get through.
func drawWall() {
    fill(CGRect(x: 0, y: 0, width: size, height: size), rgb(0x1c5cab))
    let left: CGFloat = 192, width: CGFloat = 640, gap: CGFloat = 28, height: CGFloat = 150, bottom: CGFloat = 259
    let full = (width - gap) / 2, half = (width - 2 * gap - full) / 2
    let rows: [[CGFloat]] = [[full, full], [half, full, half], [full, full]]
    for (index, bricks) in rows.enumerated() {
        var x = left
        let y = bottom + CGFloat(index) * (height + gap)
        for brick in bricks {
            fill(CGRect(x: x, y: y, width: brick, height: height), rgb(0xffffff), radius: 18)
            x += brick + gap
        }
    }
}

/// One solid block with a diagonal cut through it.
func drawSlash() {
    let background = rgb(0x2a78d6)
    fill(CGRect(x: 0, y: 0, width: size, height: size), background)
    fill(CGRect(x: 232, y: 232, width: 560, height: 560), rgb(0xffffff), radius: 96)
    context.setStrokeColor(background)
    context.setLineWidth(84)
    context.setLineCap(.butt)
    context.move(to: CGPoint(x: 180, y: 180))
    context.addLine(to: CGPoint(x: 844, y: 844))
    context.strokePath()
}

/// A flat three-tone cube.
func drawCube() {
    fill(CGRect(x: 0, y: 0, width: size, height: size), rgb(0x0d366b))
    let center = CGPoint(x: 512, y: 512), edge: CGFloat = 300, rise = edge * 0.5, drop = edge * 0.866
    let top = CGPoint(x: center.x, y: center.y + edge), bottom = CGPoint(x: center.x, y: center.y - edge)
    let leftUp = CGPoint(x: center.x - drop, y: center.y + rise), leftDown = CGPoint(x: center.x - drop, y: center.y - rise)
    let rightUp = CGPoint(x: center.x + drop, y: center.y + rise), rightDown = CGPoint(x: center.x + drop, y: center.y - rise)
    polygon([top, rightUp, center, leftUp], rgb(0xffffff))
    polygon([leftUp, center, bottom, leftDown], rgb(0x86b6ef))
    polygon([center, rightUp, rightDown, bottom], rgb(0x3987e5))
}

switch style {
case "slash": drawSlash()
case "cube": drawCube()
default: drawWall()
}

let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("could not write \(output.path)") }
print("wrote \(output.path)")
