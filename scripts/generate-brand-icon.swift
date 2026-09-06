#!/usr/bin/env swift
// Lazyest icon family. Code-native vector artwork; no external assets or fonts.
import AppKit
import Foundation

let products = ["setup", "flow", "cleaner", "work", "workspace", "yoyak", "presence"]
let args = Array(CommandLine.arguments.dropFirst())
guard args.count == 2, products.contains(args[0]) else {
    fputs("usage: generate-icons.swift <setup|flow|cleaner|work|workspace|yoyak|presence> <output.iconset>\n", stderr)
    exit(64)
}
let output = URL(fileURLWithPath: args[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let sizes: [(String, Int)] = [("icon_16x16",16),("icon_16x16@2x",32),("icon_32x32",32),
    ("icon_32x32@2x",64),("icon_128x128",128),("icon_128x128@2x",256),
    ("icon_256x256",256),("icon_256x256@2x",512),("icon_512x512",512),("icon_512x512@2x",1024)]

func ink(_ hex: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255)/255, green: CGFloat((hex >> 8) & 255)/255,
            blue: CGFloat(hex & 255)/255, alpha: 1)
}
func line(_ points: [(CGFloat, CGFloat)], color: NSColor = ink(0xF4F7FC), width: CGFloat = 48) {
    let p = NSBezierPath()
    p.move(to: NSPoint(x: points[0].0, y: points[0].1))
    for (x,y) in points.dropFirst() { p.line(to: NSPoint(x:x,y:y)) }
    p.lineWidth = width; p.lineCapStyle = .round; p.lineJoinStyle = .round
    color.setStroke(); p.stroke()
}
func rounded(_ x: CGFloat,_ y: CGFloat,_ w: CGFloat,_ h: CGFloat,_ radius: CGFloat,
             color: NSColor, stroke: Bool = false) {
    let path = NSBezierPath(roundedRect: NSRect(x:x,y:y,width:w,height:h),xRadius:radius,yRadius:radius)
    if stroke { path.lineWidth=48; color.setStroke(); path.stroke() }
    else { color.setFill(); path.fill() }
}
func draw(_ product: String, size: Int) throws -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,
        bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep:bitmap)
    defer { NSGraphicsContext.restoreGraphicsState() }
    let transform = NSAffineTransform(); transform.scale(by:CGFloat(size)/1024); transform.concat()
    let paper = ink(0xF4F7FC), blue = ink(0x729DFF), base = ink(0x1D2636)
    rounded(64,64,896,896,208,color:base)
    // Consistent silhouette, margins, optical weight, and single blue accent.
    switch product {
    case "setup":
        for y in [CGFloat(344),512,680] { line([(292,y),(732,y)],width:44) }
        for (x,y) in [(CGFloat(422),CGFloat(680)),(616,512),(448,344)] {
            rounded(x-40,y-56,80,112,32,color:base)
            rounded(x-30,y-48,60,96,26,color:blue)
        }
    case "flow":
        let p=NSBezierPath(); p.move(to:NSPoint(x:288,y:368))
        p.curve(to:NSPoint(x:736,y:656),controlPoint1:NSPoint(x:548,y:328),controlPoint2:NSPoint(x:456,y:696))
        p.lineWidth=60; p.lineCapStyle = .round; paper.setStroke(); p.stroke()
        line([(614,688),(746,656),(714,524)],color:blue,width:56)
    case "cleaner":
        rounded(296,300,432,408,70,color:paper,stroke:true)
        line([(380,594),(644,594)],width:44)
        line([(404,452),(476,384),(624,520)],color:blue,width:50)
    case "work":
        rounded(286,310,452,360,66,color:paper,stroke:true)
        let p=NSBezierPath(); p.move(to:NSPoint(x:418,y:674)); p.line(to:NSPoint(x:418,y:708))
        p.curve(to:NSPoint(x:454,y:744),controlPoint1:NSPoint(x:418,y:736),controlPoint2:NSPoint(x:426,y:744))
        p.line(to:NSPoint(x:570,y:744)); p.curve(to:NSPoint(x:606,y:708),controlPoint1:NSPoint(x:598,y:744),controlPoint2:NSPoint(x:606,y:736))
        p.line(to:NSPoint(x:606,y:674)); p.lineWidth=48; paper.setStroke(); p.stroke()
        line([(308,522),(716,522)],color:paper,width:40)
        rounded(478,480,68,88,24,color:blue)
    case "workspace":
        rounded(278,300,468,424,66,color:paper,stroke:true)
        line([(422,322),(422,702)],width:38)
        line([(438,564),(724,564)],width:38)
        rounded(482,362,200,134,28,color:blue)
    case "yoyak":
        let p=NSBezierPath(roundedRect:NSRect(x:284,y:346,width:456,height:360),xRadius:70,yRadius:70)
        p.lineWidth=48; paper.setStroke(); p.stroke()
        line([(382,342),(382,276),(484,346)],width:46)
        line([(392,578),(632,578)],color:blue,width:44)
        line([(392,470),(556,470)],width:44)
    default:
        let ring=NSBezierPath(ovalIn:NSRect(x:300,y:300,width:424,height:424)); ring.lineWidth=44; paper.setStroke(); ring.stroke()
        line([(356,502),(438,502),(494,602),(554,414),(604,502),(670,502)],color:blue,width:42)
    }
    return bitmap.representation(using:.png,properties:[:])!
}
for (name,size) in sizes { try draw(args[0],size:size).write(to:output.appendingPathComponent(name+".png"),options:.atomic) }
let process=Process(); process.executableURL=URL(fileURLWithPath:"/usr/bin/iconutil")
process.arguments=["-c","icns",output.path,"-o",output.deletingPathExtension().appendingPathExtension("icns").path]
try process.run(); process.waitUntilExit(); guard process.terminationStatus == 0 else { exit(process.terminationStatus) }
