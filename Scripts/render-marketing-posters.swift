#!/usr/bin/swift

import AppKit
import Foundation

private let rootURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
private let posterURL = rootURL.appendingPathComponent("Docs/Media/Posters", isDirectory: true)
private let sourceURL = posterURL.appendingPathComponent("sources", isDirectory: true)
private let iconURL = rootURL.appendingPathComponent("Assets/FocusTraceIcon.png")
private let focusArtURL = sourceURL.appendingPathComponent("focus-flow-art.png")
private let featureArtURL = sourceURL.appendingPathComponent("feature-system-art.png")

private let ink = NSColor(calibratedRed: 0.075, green: 0.102, blue: 0.155, alpha: 1)
private let navy = NSColor(calibratedRed: 0.025, green: 0.080, blue: 0.240, alpha: 1)
private let muted = NSColor(calibratedRed: 0.335, green: 0.385, blue: 0.445, alpha: 1)
private let mint = NSColor(calibratedRed: 0.180, green: 0.835, blue: 0.735, alpha: 1)
private let cyan = NSColor(calibratedRed: 0.120, green: 0.610, blue: 0.930, alpha: 1)
private let coral = NSColor(calibratedRed: 0.990, green: 0.410, blue: 0.340, alpha: 1)
private let ice = NSColor(calibratedRed: 0.945, green: 0.980, blue: 0.992, alpha: 1)
private let paper = NSColor(calibratedRed: 0.982, green: 0.984, blue: 0.978, alpha: 1)
private let line = NSColor(calibratedRed: 0.760, green: 0.830, blue: 0.865, alpha: 0.55)

private struct Canvas {
    let width: Int
    let height: Int
    let representation: NSBitmapImageRep

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
        representation = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        )!
        representation.size = NSSize(width: width, height: height)
    }

    func topRect(x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat) -> NSRect {
        NSRect(
            x: x,
            y: CGFloat(self.height) - y - height,
            width: width,
            height: height
        )
    }

    func begin() {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
        NSGraphicsContext.current?.imageInterpolation = .high
    }

    func finish(to url: URL) throws {
        NSGraphicsContext.restoreGraphicsState()
        guard let data = representation.representation(
            using: .png,
            properties: [.compressionFactor: 0.92]
        ) else {
            throw NSError(
                domain: "FocusTracePoster",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "无法编码海报 PNG"]
            )
        }
        try data.write(to: url, options: .atomic)
    }
}

private func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
    NSFont.systemFont(ofSize: size, weight: weight)
}

private func drawText(
    _ text: String,
    in rect: NSRect,
    size: CGFloat,
    weight: NSFont.Weight = .regular,
    color: NSColor = ink,
    lineSpacing: CGFloat = 0,
    alignment: NSTextAlignment = .left,
    tracking: CGFloat = 0
) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = alignment
    paragraph.lineBreakMode = .byWordWrapping
    paragraph.lineSpacing = lineSpacing
    let attributed = NSAttributedString(
        string: text,
        attributes: [
            .font: font(size: size, weight: weight),
            .foregroundColor: color,
            .paragraphStyle: paragraph,
            .kern: tracking
        ]
    )
    attributed.draw(
        with: rect,
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
}

private func fill(_ color: NSColor, rect: NSRect) {
    color.setFill()
    rect.fill()
}

private func roundedRect(
    _ rect: NSRect,
    radius: CGFloat,
    fill color: NSColor,
    stroke: NSColor? = nil,
    lineWidth: CGFloat = 1
) {
    let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    color.setFill()
    path.fill()
    if let stroke {
        stroke.setStroke()
        path.lineWidth = lineWidth
        path.stroke()
    }
}

private func drawImageCover(
    _ image: NSImage,
    in destination: NSRect,
    opacity: CGFloat = 1
) {
    let sourceSize = image.size
    let destinationAspect = destination.width / destination.height
    let sourceAspect = sourceSize.width / sourceSize.height
    var source = NSRect(origin: .zero, size: sourceSize)
    if sourceAspect > destinationAspect {
        let newWidth = sourceSize.height * destinationAspect
        source.origin.x = (sourceSize.width - newWidth) / 2
        source.size.width = newWidth
    } else {
        let newHeight = sourceSize.width / destinationAspect
        source.origin.y = (sourceSize.height - newHeight) / 2
        source.size.height = newHeight
    }
    image.draw(
        in: destination,
        from: source,
        operation: .sourceOver,
        fraction: opacity,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

private func drawImageFit(_ image: NSImage, in destination: NSRect) {
    let source = image.size
    let scale = min(destination.width / source.width, destination.height / source.height)
    let width = source.width * scale
    let height = source.height * scale
    image.draw(
        in: NSRect(
            x: destination.midX - width / 2,
            y: destination.midY - height / 2,
            width: width,
            height: height
        ),
        from: .zero,
        operation: .sourceOver,
        fraction: 1,
        respectFlipped: false,
        hints: [.interpolation: NSImageInterpolation.high]
    )
}

private func clippedImage(
    _ image: NSImage,
    in destination: NSRect,
    radius: CGFloat,
    opacity: CGFloat = 1
) {
    NSGraphicsContext.saveGraphicsState()
    NSBezierPath(
        roundedRect: destination,
        xRadius: radius,
        yRadius: radius
    ).addClip()
    drawImageCover(image, in: destination, opacity: opacity)
    NSGraphicsContext.restoreGraphicsState()
}

private func drawPill(
    _ label: String,
    canvas: Canvas,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    fillColor: NSColor,
    textColor: NSColor
) {
    let rect = canvas.topRect(x: x, y: y, width: width, height: 54)
    roundedRect(rect, radius: 27, fill: fillColor)
    drawText(
        label,
        in: canvas.topRect(x: x, y: y + 11, width: width, height: 34),
        size: 21,
        weight: .semibold,
        color: textColor,
        alignment: .center
    )
}

private func drawBrand(
    canvas: Canvas,
    icon: NSImage,
    x: CGFloat,
    y: CGFloat,
    iconSize: CGFloat,
    wordSize: CGFloat
) {
    drawImageFit(
        icon,
        in: canvas.topRect(
            x: x,
            y: y,
            width: iconSize,
            height: iconSize
        )
    )
    drawText(
        "FocusTrace",
        in: canvas.topRect(
            x: x + iconSize + 24,
            y: y + iconSize * 0.18,
            width: 420,
            height: iconSize
        ),
        size: wordSize,
        weight: .bold,
        color: ink,
        tracking: -1.2
    )
}

private func renderProductSocial(icon: NSImage, art: NSImage) throws {
    let canvas = Canvas(width: 1440, height: 1800)
    canvas.begin()
    fill(paper, rect: canvas.topRect(x: 0, y: 0, width: 1440, height: 1800))
    drawImageCover(
        art,
        in: canvas.topRect(x: 0, y: 300, width: 1440, height: 1500),
        opacity: 0.96
    )

    let textPanel = canvas.topRect(x: 64, y: 62, width: 1010, height: 690)
    roundedRect(
        textPanel,
        radius: 44,
        fill: NSColor.white.withAlphaComponent(0.91),
        stroke: line,
        lineWidth: 1.5
    )
    drawBrand(canvas: canvas, icon: icon, x: 108, y: 102, iconSize: 108, wordSize: 50)
    drawText(
        "看清切换，\n不丢上下文。",
        in: canvas.topRect(x: 108, y: 276, width: 860, height: 210),
        size: 82,
        weight: .bold,
        color: ink,
        lineSpacing: 5,
        tracking: -2
    )
    drawText(
        "为 Agent 与多任务并发时代设计的\nmacOS 专注轨迹工具",
        in: canvas.topRect(x: 112, y: 520, width: 840, height: 106),
        size: 34,
        weight: .medium,
        color: muted,
        lineSpacing: 10
    )
    drawPill(
        "本地运行",
        canvas: canvas,
        x: 108,
        y: 652,
        width: 142,
        fillColor: navy,
        textColor: .white
    )
    drawPill(
        "不读工作内容",
        canvas: canvas,
        x: 266,
        y: 652,
        width: 190,
        fillColor: mint.withAlphaComponent(0.18),
        textColor: navy
    )
    drawPill(
        "开源",
        canvas: canvas,
        x: 472,
        y: 652,
        width: 108,
        fillColor: cyan.withAlphaComponent(0.16),
        textColor: navy
    )

    let footer = canvas.topRect(x: 68, y: 1600, width: 1304, height: 136)
    roundedRect(
        footer,
        radius: 34,
        fill: navy.withAlphaComponent(0.90),
        stroke: NSColor.white.withAlphaComponent(0.25)
    )
    fill(
        mint,
        rect: canvas.topRect(x: 108, y: 1642, width: 10, height: 50)
    )
    drawText(
        "记录轨迹 · 接住需求 · 用证据改善注意力",
        in: canvas.topRect(x: 146, y: 1637, width: 1110, height: 64),
        size: 31,
        weight: .semibold,
        color: .white,
        tracking: 0.2
    )
    try canvas.finish(
        to: posterURL.appendingPathComponent("focustrace-product-social.png")
    )
}

private func renderProductGitHub(icon: NSImage, art: NSImage) throws {
    let canvas = Canvas(width: 1600, height: 900)
    canvas.begin()
    fill(paper, rect: canvas.topRect(x: 0, y: 0, width: 1600, height: 900))
    drawImageCover(
        art,
        in: canvas.topRect(x: 820, y: 0, width: 780, height: 900),
        opacity: 1
    )
    let gradient = NSGradient(colors: [
        paper,
        paper,
        paper.withAlphaComponent(0)
    ])!
    gradient.draw(
        in: canvas.topRect(x: 690, y: 0, width: 320, height: 900),
        angle: 0
    )

    drawBrand(canvas: canvas, icon: icon, x: 84, y: 70, iconSize: 90, wordSize: 42)
    drawText(
        "看清切换，\n不丢上下文。",
        in: canvas.topRect(x: 84, y: 230, width: 700, height: 168),
        size: 67,
        weight: .bold,
        color: ink,
        lineSpacing: 2,
        tracking: -1.8
    )
    drawText(
        "为 Agent 与多任务并发时代设计的\nmacOS 专注轨迹工具",
        in: canvas.topRect(x: 88, y: 442, width: 680, height: 100),
        size: 29,
        weight: .medium,
        color: muted,
        lineSpacing: 8
    )
    drawPill(
        "本地运行",
        canvas: canvas,
        x: 84,
        y: 596,
        width: 138,
        fillColor: navy,
        textColor: .white
    )
    drawPill(
        "不读工作内容",
        canvas: canvas,
        x: 238,
        y: 596,
        width: 184,
        fillColor: mint.withAlphaComponent(0.18),
        textColor: navy
    )
    drawPill(
        "macOS 14+",
        canvas: canvas,
        x: 438,
        y: 596,
        width: 154,
        fillColor: cyan.withAlphaComponent(0.14),
        textColor: navy
    )
    drawText(
        "记录轨迹  ·  接住需求  ·  用证据改善注意力",
        in: canvas.topRect(x: 86, y: 742, width: 710, height: 52),
        size: 24,
        weight: .semibold,
        color: navy
    )
    drawText(
        "github.com/cornliu26/FocusTrace",
        in: canvas.topRect(x: 86, y: 808, width: 650, height: 34),
        size: 19,
        weight: .medium,
        color: muted
    )
    try canvas.finish(
        to: posterURL.appendingPathComponent("focustrace-product-github.png")
    )
}

private struct FeatureCopy {
    let number: String
    let title: String
    let body: String
    let accent: NSColor
}

private let features = [
    FeatureCopy(
        number: "01",
        title: "看见碎片",
        body: "时间轴还原应用与工作流切换，\n看清注意力去了哪里。",
        accent: cyan
    ),
    FeatureCopy(
        number: "02",
        title: "接住需求",
        body: "口头需求先进入需求箱，再按时效、\n优先级和工作流推进。",
        accent: mint
    ),
    FeatureCopy(
        number: "03",
        title: "用证据改进",
        body: "训练、复盘与 Codex 行动建议，\n每次只解决一个问题。",
        accent: coral
    )
]

private func drawFeatureCard(
    _ feature: FeatureCopy,
    canvas: Canvas,
    x: CGFloat,
    y: CGFloat,
    width: CGFloat,
    height: CGFloat,
    horizontal: Bool
) {
    let rect = canvas.topRect(x: x, y: y, width: width, height: height)
    roundedRect(
        rect,
        radius: horizontal ? 30 : 36,
        fill: NSColor.white.withAlphaComponent(0.94),
        stroke: line,
        lineWidth: 1.5
    )
    let badgeSize: CGFloat = horizontal ? 48 : 66
    let badge = canvas.topRect(
        x: x + (horizontal ? 26 : 32),
        y: y + (horizontal ? 28 : 38),
        width: badgeSize,
        height: badgeSize
    )
    roundedRect(
        badge,
        radius: badgeSize / 2,
        fill: feature.accent.withAlphaComponent(0.16),
        stroke: feature.accent.withAlphaComponent(0.45)
    )
    drawText(
        feature.number,
        in: canvas.topRect(
            x: badge.minX,
            y: y + (horizontal ? 40 : 54),
            width: badgeSize,
            height: 30
        ),
        size: horizontal ? 17 : 21,
        weight: .bold,
        color: navy,
        alignment: .center
    )
    let titleX = horizontal ? x + 28 : x + 130
    let titleY = horizontal ? y + 96 : y + 38
    drawText(
        feature.title,
        in: canvas.topRect(
            x: titleX,
            y: titleY,
            width: width - (horizontal ? 56 : 170),
            height: 54
        ),
        size: horizontal ? 31 : 37,
        weight: .bold,
        color: ink,
        tracking: -0.5
    )
    let bodyX = horizontal ? x + 28 : x + 130
    let bodyY = horizontal ? y + 152 : y + 94
    drawText(
        feature.body,
        in: canvas.topRect(
            x: bodyX,
            y: bodyY,
            width: width - (horizontal ? 56 : 170),
            height: height - (horizontal ? 170 : 112)
        ),
        size: horizontal ? 20 : 26,
        weight: .medium,
        color: muted,
        lineSpacing: horizontal ? 5 : 8
    )
}

private func renderFeaturesSocial(icon: NSImage, art: NSImage) throws {
    let canvas = Canvas(width: 1440, height: 1800)
    canvas.begin()
    fill(ice, rect: canvas.topRect(x: 0, y: 0, width: 1440, height: 1800))
    let topGradient = NSGradient(colors: [paper, ice])!
    topGradient.draw(
        in: canvas.topRect(x: 0, y: 0, width: 1440, height: 560),
        angle: -90
    )
    drawBrand(canvas: canvas, icon: icon, x: 78, y: 66, iconSize: 78, wordSize: 35)
    drawText(
        "把一天的碎片，\n重新连成工作流。",
        in: canvas.topRect(x: 78, y: 188, width: 1120, height: 174),
        size: 68,
        weight: .bold,
        color: ink,
        lineSpacing: 4,
        tracking: -1.5
    )
    drawText(
        "三个环节，构成一条完整的专注闭环",
        in: canvas.topRect(x: 82, y: 384, width: 900, height: 46),
        size: 29,
        weight: .medium,
        color: muted
    )
    clippedImage(
        art,
        in: canvas.topRect(x: 50, y: 482, width: 1340, height: 500),
        radius: 42,
        opacity: 0.96
    )
    for (index, feature) in features.enumerated() {
        drawFeatureCard(
            feature,
            canvas: canvas,
            x: 64,
            y: 1012 + CGFloat(index) * 224,
            width: 1312,
            height: 196,
            horizontal: false
        )
    }
    drawText(
        "LOCAL-FIRST  ·  不读取窗口标题、网页地址或输入内容",
        in: canvas.topRect(x: 76, y: 1718, width: 1288, height: 40),
        size: 20,
        weight: .semibold,
        color: navy,
        alignment: .center,
        tracking: 0.6
    )
    try canvas.finish(
        to: posterURL.appendingPathComponent("focustrace-features-social.png")
    )
}

private func renderFeaturesGitHub(icon: NSImage, art: NSImage) throws {
    let canvas = Canvas(width: 1600, height: 900)
    canvas.begin()
    fill(ice, rect: canvas.topRect(x: 0, y: 0, width: 1600, height: 900))
    drawImageCover(
        art,
        in: canvas.topRect(x: 0, y: 0, width: 1600, height: 900),
        opacity: 0.90
    )
    fill(
        NSColor.white.withAlphaComponent(0.50),
        rect: canvas.topRect(x: 0, y: 0, width: 1600, height: 900)
    )
    drawBrand(canvas: canvas, icon: icon, x: 52, y: 44, iconSize: 62, wordSize: 28)
    drawText(
        "把一天的碎片，重新连成工作流。",
        in: canvas.topRect(x: 52, y: 132, width: 1220, height: 82),
        size: 52,
        weight: .bold,
        color: ink,
        tracking: -1.2
    )
    drawText(
        "看见碎片  ·  接住需求  ·  用证据改进",
        in: canvas.topRect(x: 56, y: 226, width: 1100, height: 45),
        size: 26,
        weight: .semibold,
        color: navy
    )
    for (index, feature) in features.enumerated() {
        drawFeatureCard(
            feature,
            canvas: canvas,
            x: 44 + CGFloat(index) * 518,
            y: 536,
            width: 480,
            height: 290,
            horizontal: true
        )
    }
    drawText(
        "LOCAL-FIRST  ·  不读取窗口标题、网页地址或输入内容",
        in: canvas.topRect(x: 1050, y: 62, width: 492, height: 36),
        size: 16,
        weight: .semibold,
        color: navy,
        alignment: .right,
        tracking: 0.4
    )
    try canvas.finish(
        to: posterURL.appendingPathComponent("focustrace-features-github.png")
    )
}

try FileManager.default.createDirectory(
    at: posterURL,
    withIntermediateDirectories: true
)
guard let icon = NSImage(contentsOf: iconURL),
      let focusArt = NSImage(contentsOf: focusArtURL),
      let featureArt = NSImage(contentsOf: featureArtURL)
else {
    throw NSError(
        domain: "FocusTracePoster",
        code: 2,
        userInfo: [NSLocalizedDescriptionKey: "海报源图缺失"]
    )
}

try renderProductSocial(icon: icon, art: focusArt)
try renderProductGitHub(icon: icon, art: focusArt)
try renderFeaturesSocial(icon: icon, art: featureArt)
try renderFeaturesGitHub(icon: icon, art: featureArt)

print("Rendered FocusTrace marketing posters in \(posterURL.path)")
