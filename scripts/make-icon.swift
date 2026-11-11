// 앱 아이콘(1024px PNG)을 그린다. 사용: swift make-icon.swift <출력.png>
//
// HTML5 방패 로고를 뒤집은 형태: 마크"업"의 반대인 마크"다운".
// 방패는 위아래를 뒤집고, 색은 HTML5 주황의 보색인 파랑, 숫자 5 자리에 M.
import AppKit

let output = CommandLine.arguments[1]

let blueDark = NSColor(srgbRed: 0.149, green: 0.447, blue: 0.894, alpha: 1)   // #2672E4
let blueLight = NSColor(srgbRed: 0.161, green: 0.580, blue: 0.945, alpha: 1)  // #2994F1
let glyphShade = NSColor(white: 0.92, alpha: 1)

func polygon(_ points: [(CGFloat, CGFloat)]) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: points[0].0, y: points[0].1))
    for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.0, y: point.1)) }
    path.closeSubpath()
    return path
}

// 좌표계: 1000 × 1000, 원점은 왼쪽 아래
let shield = polygon([(140, 90), (860, 90), (795, 825), (500, 910), (205, 825)])
let lightHalf = polygon([(500, 150), (797, 150), (742, 778), (500, 848)])
let letterM = polygon([
    (310, 260), (310, 640), (405, 640), (500, 478), (595, 640), (690, 640), (690, 260),
    (604, 260), (604, 493), (500, 322), (396, 493), (396, 260),
])

let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024,
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let context = NSGraphicsContext.current!.cgContext
context.scaleBy(x: 1.024, y: 1.024)

context.addPath(shield)
context.setFillColor(blueDark.cgColor)
context.fillPath()

context.addPath(lightHalf)
context.setFillColor(blueLight.cgColor)
context.fillPath()

// 글자도 HTML5 처럼 왼쪽 절반만 살짝 어둡게
context.addPath(letterM)
context.setFillColor(glyphShade.cgColor)
context.fillPath()
context.clip(to: CGRect(x: 500, y: 0, width: 500, height: 1000))
context.addPath(letterM)
context.setFillColor(NSColor.white.cgColor)
context.fillPath()

NSGraphicsContext.restoreGraphicsState()
try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
