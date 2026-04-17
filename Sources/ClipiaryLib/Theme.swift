import Foundation
import SwiftUI

// MARK: - Primitive Theme Types

struct ThemeFill: Codable, Sendable, Equatable {
    var color: String?
    var gradient: [String]?
    var from: String?
    var to: String?
    var opacity: Double?
    // MeshGradient (macOS 15+)
    var mesh: [String]?
    var meshColumns: Int?
    var meshRows: Int?
    var meshPoints: [[Double]]?

    static func solid(_ hex: String, opacity: Double? = nil) -> ThemeFill {
        ThemeFill(color: hex, opacity: opacity)
    }

    static func linearGradient(_ colors: [String], from: String = "top", to: String = "bottom", opacity: Double? = nil) -> ThemeFill {
        ThemeFill(gradient: colors, from: from, to: to, opacity: opacity)
    }

    static func meshGradient(_ colors: [String], columns: Int, rows: Int, points: [[Double]]? = nil, opacity: Double? = nil) -> ThemeFill {
        ThemeFill(opacity: opacity, mesh: colors, meshColumns: columns, meshRows: rows, meshPoints: points)
    }

    func resolved(fallback: Color, defaultOpacity: Double = 1.0) -> AnyShapeStyle {
        let op = opacity ?? defaultOpacity
        if let meshColors = mesh, let cols = meshColumns, let rows = meshRows, cols * rows == meshColors.count {
            let colors = meshColors.compactMap { Color(hex: $0) }
            guard colors.count == cols * rows else { return AnyShapeStyle(fallback.opacity(op)) }
            if #available(macOS 15, *) {
                let pts: [SIMD2<Float>]
                if let custom = meshPoints, custom.count == cols * rows {
                    pts = custom.map { pair in SIMD2<Float>(Float(pair[0]), Float(pair[1])) }
                } else {
                    pts = (0..<rows).flatMap { row in
                        (0..<cols).map { col in
                            SIMD2<Float>(
                                cols > 1 ? Float(col) / Float(cols - 1) : 0.5,
                                rows > 1 ? Float(row) / Float(rows - 1) : 0.5
                            )
                        }
                    }
                }
                return AnyShapeStyle(MeshGradient(width: cols, height: rows, points: pts, colors: colors).opacity(op))
            }
            // macOS 14 fallback: diagonal linear gradient from top-left to bottom-right corner colors
            return AnyShapeStyle(LinearGradient(
                colors: [colors[0], colors[cols * rows - 1]],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).opacity(op))
        }
        if let gradient, gradient.count >= 2 {
            let colors = gradient.compactMap { Color(hex: $0) }
            guard colors.count >= 2 else { return AnyShapeStyle(fallback.opacity(op)) }
            return AnyShapeStyle(
                LinearGradient(
                    colors: colors,
                    startPoint: unitPoint(from ?? "top"),
                    endPoint: unitPoint(to ?? "bottom")
                ).opacity(op)
            )
        }
        let base = Color(hex: color) ?? fallback
        return AnyShapeStyle(base.opacity(op))
    }

    private func unitPoint(_ name: String) -> UnitPoint {
        switch name {
        case "top": .top
        case "bottom": .bottom
        case "leading": .leading
        case "trailing": .trailing
        case "topLeading": .topLeading
        case "topTrailing": .topTrailing
        case "bottomLeading": .bottomLeading
        case "bottomTrailing": .bottomTrailing
        case "center": .center
        default: .top
        }
    }
}

struct ThemeBorder: Codable, Sendable, Equatable {
    var color: String?
    var width: CGFloat?
    var opacity: Double?
    var dash: [CGFloat]?
    /// Animation style: `"flash"` (brightness pulse) or `"sweep"` (draw-on from top-left + bottom-right).
    var animation: String?
    /// Duration of the border animation in seconds. Defaults to 0.6 for sweep, 0.6 for flash.
    var animationDuration: Double?
}

struct ThemeGlow: Codable, Sendable, Equatable {
    var color: String?
    var radius: CGFloat?
    var opacity: Double?
    // Optional inner layer for double-glow neon effect
    var innerRadius: CGFloat?
    var innerOpacity: Double?
}

struct ThemeInnerShadow: Codable, Sendable, Equatable {
    /// Shadow color hex. Defaults to black.
    var color: String?
    /// Blur radius. Defaults to 4.
    var radius: CGFloat?
    /// Shadow opacity. Defaults to 0.4.
    var opacity: Double?
    /// Horizontal offset (positive = right). Defaults to 0.
    var x: CGFloat?
    /// Vertical offset (positive = down). Defaults to 0.
    var y: CGFloat?
}

// MARK: - Theme

struct Theme: Codable, Sendable, Equatable {
    var id: String
    var name: String
    var options: Options
    var fills: Fills
    var colors: Colors
    var borders: Borders
    var effects: Effects
    var cornerRadii: CornerRadii
    var spacing: Spacing
    var fonts: Fonts

    struct Options: Codable, Sendable, Equatable {
        /// macOS vibrancy material for the panel background.
        /// Accepted values: `"ultraThin"`, `"thin"`, `"regular"`, `"thick"`, `"ultraThick"`.
        /// `nil` (or omitted) = no material; panel uses `fills.panel` instead.
        ///
        /// Legacy JSON key `useMaterial: true` is read as `"regular"` during decoding.
        var material: String?
        var useSystemAccent: Bool
        var appearance: String
        var animatedPanel: Bool
        var animatedPanelColor: String?
        var animatedPanelPeriod: Double?
        /// Gaussian blur radius applied to panel content behind the favorites picker overlay.
        /// nil = no blur (plain darkened overlay).
        var overlayBlurRadius: Double?

        static let `default` = Options(
            material: "regular",
            useSystemAccent: true,
            appearance: "dark",
            animatedPanel: false
        )

        init(material: String? = Self.default.material,
             useSystemAccent: Bool = Self.default.useSystemAccent,
             appearance: String = Self.default.appearance,
             animatedPanel: Bool = false,
             animatedPanelColor: String? = nil,
             animatedPanelPeriod: Double? = nil,
             overlayBlurRadius: Double? = nil) {
            self.material = material
            self.useSystemAccent = useSystemAccent
            self.appearance = appearance
            self.animatedPanel = animatedPanel
            self.animatedPanelColor = animatedPanelColor
            self.animatedPanelPeriod = animatedPanelPeriod
            self.overlayBlurRadius = overlayBlurRadius
        }

        // Convenience init that accepts the legacy Bool for call sites that haven't migrated.
        init(useMaterial: Bool,
             useSystemAccent: Bool = Self.default.useSystemAccent,
             appearance: String = Self.default.appearance,
             animatedPanel: Bool = false,
             animatedPanelColor: String? = nil,
             animatedPanelPeriod: Double? = nil,
             overlayBlurRadius: Double? = nil) {
            self.material = useMaterial ? "regular" : nil
            self.useSystemAccent = useSystemAccent
            self.appearance = appearance
            self.animatedPanel = animatedPanel
            self.animatedPanelColor = animatedPanelColor
            self.animatedPanelPeriod = animatedPanelPeriod
            self.overlayBlurRadius = overlayBlurRadius
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let d = Self.default
            // New-style: material string takes precedence.
            if let materialStr = try container.decodeIfPresent(String.self, forKey: .material) {
                // "none" is the sentinel for an explicit "no material" choice.
                material = materialStr == "none" ? nil : materialStr
            } else if let legacyBool = try container.decodeIfPresent(Bool.self, forKey: .useMaterial) {
                // Legacy `useMaterial: true/false` — map to "regular" or nil.
                material = legacyBool ? "regular" : nil
            } else {
                material = d.material
            }
            useSystemAccent = try container.decodeIfPresent(Bool.self, forKey: .useSystemAccent) ?? d.useSystemAccent
            appearance = try container.decodeIfPresent(String.self, forKey: .appearance) ?? d.appearance
            animatedPanel = try container.decodeIfPresent(Bool.self, forKey: .animatedPanel) ?? d.animatedPanel
            animatedPanelColor = try container.decodeIfPresent(String.self, forKey: .animatedPanelColor)
            animatedPanelPeriod = try container.decodeIfPresent(Double.self, forKey: .animatedPanelPeriod)
            overlayBlurRadius = try container.decodeIfPresent(Double.self, forKey: .overlayBlurRadius)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            // Encode nil as "none" so a deliberate "no material" choice survives reload.
            // Absent key would fall through to the default ("regular") on decode.
            try container.encode(material ?? "none", forKey: .material)
            try container.encode(useSystemAccent, forKey: .useSystemAccent)
            try container.encode(appearance, forKey: .appearance)
            try container.encode(animatedPanel, forKey: .animatedPanel)
            try container.encodeIfPresent(animatedPanelColor, forKey: .animatedPanelColor)
            try container.encodeIfPresent(animatedPanelPeriod, forKey: .animatedPanelPeriod)
            try container.encodeIfPresent(overlayBlurRadius, forKey: .overlayBlurRadius)
        }

        enum CodingKeys: String, CodingKey {
            case material, useMaterial, useSystemAccent, appearance
            case animatedPanel, animatedPanelColor, animatedPanelPeriod
            case overlayBlurRadius
        }
    }

    struct Fills: Codable, Sendable, Equatable {
        var panel: ThemeFill
        /// Fill for the outer panel shell background (same as `panel` by default, but can differ).
        var contentArea: ThemeFill
        var tabBar: ThemeFill
        var tabButtonSelected: ThemeFill?
        var rowSelected: ThemeFill
        var rowHovered: ThemeFill
        var card: ThemeFill
        var overlay: ThemeFill

        static let panelDefaultOpacity = 0.85
        static let tabBarDefaultOpacity = 0.05
        static let rowSelectedDefaultOpacity = 0.18
        static let rowHoveredDefaultOpacity = 0.09
        static let cardDefaultOpacity = 0.15
        static let overlayDefaultOpacity = 0.15

        static let `default` = Fills(
            panel: .solid("#1E1E1E", opacity: panelDefaultOpacity),
            contentArea: .solid("#1E1E1E", opacity: panelDefaultOpacity),
            tabBar: .solid("#000000", opacity: tabBarDefaultOpacity),
            tabButtonSelected: nil,
            rowSelected: ThemeFill(opacity: rowSelectedDefaultOpacity),
            rowHovered: ThemeFill(opacity: rowHoveredDefaultOpacity),
            card: .solid("#000000", opacity: cardDefaultOpacity),
            overlay: .solid("#000000", opacity: overlayDefaultOpacity)
        )

        init(
            panel: ThemeFill = Self.default.panel,
            contentArea: ThemeFill? = nil,
            tabBar: ThemeFill = Self.default.tabBar,
            tabButtonSelected: ThemeFill? = nil,
            rowSelected: ThemeFill = Self.default.rowSelected,
            rowHovered: ThemeFill = Self.default.rowHovered,
            card: ThemeFill = Self.default.card,
            overlay: ThemeFill = Self.default.overlay
        ) {
            self.panel = panel
            self.contentArea = contentArea ?? panel
            self.tabBar = tabBar
            self.tabButtonSelected = tabButtonSelected
            self.rowSelected = rowSelected
            self.rowHovered = rowHovered
            self.card = card
            self.overlay = overlay
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let d = Self.default
            panel = try container.decodeIfPresent(ThemeFill.self, forKey: .panel) ?? d.panel
            // Legacy JSON without contentArea inherits from panel.
            contentArea = try container.decodeIfPresent(ThemeFill.self, forKey: .contentArea) ?? panel
            tabBar = try container.decodeIfPresent(ThemeFill.self, forKey: .tabBar) ?? d.tabBar
            tabButtonSelected = try container.decodeIfPresent(ThemeFill.self, forKey: .tabButtonSelected)
            rowSelected = try container.decodeIfPresent(ThemeFill.self, forKey: .rowSelected) ?? d.rowSelected
            rowHovered = try container.decodeIfPresent(ThemeFill.self, forKey: .rowHovered) ?? d.rowHovered
            card = try container.decodeIfPresent(ThemeFill.self, forKey: .card) ?? d.card
            overlay = try container.decodeIfPresent(ThemeFill.self, forKey: .overlay) ?? d.overlay
        }
    }

    struct Colors: Codable, Sendable, Equatable {
        var accent: String?
        var pillBackground: String?
        var pillBackgroundOpacity: Double?
        var shortcutKeyBackground: String?
        var shortcutKeyBackgroundOpacity: Double?
        var cardStroke: String?
        var cardStrokeOpacity: Double?
        var textPrimary: String?
        var textSecondary: String?
        var textTertiary: String?
        var imageIndicator: String?
        var statusReady: String?
        var statusWarning: String?
        var gaugeUnfilled: String?
        var gaugeUnfilledOpacity: Double?
        var searchHighlight: String?
        var searchHighlightBackground: String?
        var searchHighlightBackgroundOpacity: Double?
        var separator: String?
        var separatorOpacity: Double?

        static let `default` = Colors(
            accent: "#007AFF",
            pillBackground: nil,
            pillBackgroundOpacity: 0.12,
            shortcutKeyBackground: "#000000",
            shortcutKeyBackgroundOpacity: 0.06,
            cardStroke: "#FFFFFF",
            cardStrokeOpacity: 0.08,
            textPrimary: nil,
            textSecondary: nil,
            textTertiary: nil,
            imageIndicator: "#FF9500",
            statusReady: "#34C759",
            statusWarning: "#FF9500",
            gaugeUnfilled: nil,
            gaugeUnfilledOpacity: 0.15,
            searchHighlight: nil,
            searchHighlightBackground: nil,
            searchHighlightBackgroundOpacity: 0.15,
            separator: nil,
            separatorOpacity: nil
        )

        init(
            accent: String? = nil,
            pillBackground: String? = nil, pillBackgroundOpacity: Double? = nil,
            shortcutKeyBackground: String? = nil, shortcutKeyBackgroundOpacity: Double? = nil,
            cardStroke: String? = nil, cardStrokeOpacity: Double? = nil,
            textPrimary: String? = nil, textSecondary: String? = nil, textTertiary: String? = nil,
            imageIndicator: String? = nil, statusReady: String? = nil, statusWarning: String? = nil,
            gaugeUnfilled: String? = nil, gaugeUnfilledOpacity: Double? = nil,
            searchHighlight: String? = nil, searchHighlightBackground: String? = nil, searchHighlightBackgroundOpacity: Double? = nil,
            separator: String? = nil, separatorOpacity: Double? = nil
        ) {
            self.accent = accent
            self.pillBackground = pillBackground
            self.pillBackgroundOpacity = pillBackgroundOpacity
            self.shortcutKeyBackground = shortcutKeyBackground
            self.shortcutKeyBackgroundOpacity = shortcutKeyBackgroundOpacity
            self.cardStroke = cardStroke
            self.cardStrokeOpacity = cardStrokeOpacity
            self.textPrimary = textPrimary
            self.textSecondary = textSecondary
            self.textTertiary = textTertiary
            self.imageIndicator = imageIndicator
            self.statusReady = statusReady
            self.statusWarning = statusWarning
            self.gaugeUnfilled = gaugeUnfilled
            self.gaugeUnfilledOpacity = gaugeUnfilledOpacity
            self.searchHighlight = searchHighlight
            self.searchHighlightBackground = searchHighlightBackground
            self.searchHighlightBackgroundOpacity = searchHighlightBackgroundOpacity
            self.separator = separator
            self.separatorOpacity = separatorOpacity
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let d = Self.default
            accent = try container.decodeIfPresent(String.self, forKey: .accent) ?? d.accent
            pillBackground = try container.decodeIfPresent(String.self, forKey: .pillBackground) ?? d.pillBackground
            pillBackgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .pillBackgroundOpacity) ?? d.pillBackgroundOpacity
            shortcutKeyBackground = try container.decodeIfPresent(String.self, forKey: .shortcutKeyBackground) ?? d.shortcutKeyBackground
            shortcutKeyBackgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .shortcutKeyBackgroundOpacity) ?? d.shortcutKeyBackgroundOpacity
            cardStroke = try container.decodeIfPresent(String.self, forKey: .cardStroke) ?? d.cardStroke
            cardStrokeOpacity = try container.decodeIfPresent(Double.self, forKey: .cardStrokeOpacity) ?? d.cardStrokeOpacity
            textPrimary = try container.decodeIfPresent(String.self, forKey: .textPrimary) ?? d.textPrimary
            textSecondary = try container.decodeIfPresent(String.self, forKey: .textSecondary) ?? d.textSecondary
            textTertiary = try container.decodeIfPresent(String.self, forKey: .textTertiary) ?? d.textTertiary
            imageIndicator = try container.decodeIfPresent(String.self, forKey: .imageIndicator) ?? d.imageIndicator
            statusReady = try container.decodeIfPresent(String.self, forKey: .statusReady) ?? d.statusReady
            statusWarning = try container.decodeIfPresent(String.self, forKey: .statusWarning) ?? d.statusWarning
            gaugeUnfilled = try container.decodeIfPresent(String.self, forKey: .gaugeUnfilled) ?? d.gaugeUnfilled
            gaugeUnfilledOpacity = try container.decodeIfPresent(Double.self, forKey: .gaugeUnfilledOpacity) ?? d.gaugeUnfilledOpacity
            searchHighlight = try container.decodeIfPresent(String.self, forKey: .searchHighlight) ?? d.searchHighlight
            searchHighlightBackground = try container.decodeIfPresent(String.self, forKey: .searchHighlightBackground) ?? d.searchHighlightBackground
            searchHighlightBackgroundOpacity = try container.decodeIfPresent(Double.self, forKey: .searchHighlightBackgroundOpacity) ?? d.searchHighlightBackgroundOpacity
            separator = try container.decodeIfPresent(String.self, forKey: .separator)
            separatorOpacity = try container.decodeIfPresent(Double.self, forKey: .separatorOpacity)
        }
    }

    struct Borders: Codable, Sendable, Equatable {
        var panel: ThemeBorder?
        var contentArea: ThemeBorder?
        var selectedRow: ThemeBorder?
        var card: ThemeBorder?
        var searchField: ThemeBorder?
        var tabBar: ThemeBorder?

        static let `default` = Borders()

        init(
            panel: ThemeBorder? = nil, contentArea: ThemeBorder? = nil,
            selectedRow: ThemeBorder? = nil, card: ThemeBorder? = nil,
            searchField: ThemeBorder? = nil, tabBar: ThemeBorder? = nil
        ) {
            self.panel = panel
            self.contentArea = contentArea
            self.selectedRow = selectedRow
            self.card = card
            self.searchField = searchField
            self.tabBar = tabBar
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            panel = try container.decodeIfPresent(ThemeBorder.self, forKey: .panel)
            contentArea = try container.decodeIfPresent(ThemeBorder.self, forKey: .contentArea)
            selectedRow = try container.decodeIfPresent(ThemeBorder.self, forKey: .selectedRow)
            card = try container.decodeIfPresent(ThemeBorder.self, forKey: .card)
            searchField = try container.decodeIfPresent(ThemeBorder.self, forKey: .searchField)
            tabBar = try container.decodeIfPresent(ThemeBorder.self, forKey: .tabBar)
        }
    }

    struct Effects: Codable, Sendable, Equatable {
        var selectedRowGlow: ThemeGlow?
        var hoveredRowGlow: ThemeGlow?
        var panelGlow: ThemeGlow?
        var selectedRowTextGlow: ThemeGlow?
        var hoveredRowTextGlow: ThemeGlow?
        var searchHighlightTextGlow: ThemeGlow?
        var separatorGlow: ThemeGlow?
        var tabBarInnerShadow: ThemeInnerShadow?
        var contentAreaInnerShadow: ThemeInnerShadow?

        static let `default` = Effects()

        init(selectedRowGlow: ThemeGlow? = nil, hoveredRowGlow: ThemeGlow? = nil, panelGlow: ThemeGlow? = nil, selectedRowTextGlow: ThemeGlow? = nil, hoveredRowTextGlow: ThemeGlow? = nil, searchHighlightTextGlow: ThemeGlow? = nil, separatorGlow: ThemeGlow? = nil, tabBarInnerShadow: ThemeInnerShadow? = nil, contentAreaInnerShadow: ThemeInnerShadow? = nil) {
            self.selectedRowGlow = selectedRowGlow
            self.hoveredRowGlow = hoveredRowGlow
            self.panelGlow = panelGlow
            self.selectedRowTextGlow = selectedRowTextGlow
            self.hoveredRowTextGlow = hoveredRowTextGlow
            self.searchHighlightTextGlow = searchHighlightTextGlow
            self.separatorGlow = separatorGlow
            self.tabBarInnerShadow = tabBarInnerShadow
            self.contentAreaInnerShadow = contentAreaInnerShadow
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            selectedRowGlow = try container.decodeIfPresent(ThemeGlow.self, forKey: .selectedRowGlow)
            hoveredRowGlow = try container.decodeIfPresent(ThemeGlow.self, forKey: .hoveredRowGlow)
            panelGlow = try container.decodeIfPresent(ThemeGlow.self, forKey: .panelGlow)
            selectedRowTextGlow = try container.decodeIfPresent(ThemeGlow.self, forKey: .selectedRowTextGlow)
            hoveredRowTextGlow = try container.decodeIfPresent(ThemeGlow.self, forKey: .hoveredRowTextGlow)
            searchHighlightTextGlow = try container.decodeIfPresent(ThemeGlow.self, forKey: .searchHighlightTextGlow)
            separatorGlow = try container.decodeIfPresent(ThemeGlow.self, forKey: .separatorGlow)
            tabBarInnerShadow = try container.decodeIfPresent(ThemeInnerShadow.self, forKey: .tabBarInnerShadow)
            contentAreaInnerShadow = try container.decodeIfPresent(ThemeInnerShadow.self, forKey: .contentAreaInnerShadow)
        }
    }

    struct CornerRadii: Codable, Sendable, Equatable {
        var panel: CGFloat
        var contentArea: CGFloat
        var card: CGFloat
        var tabBar: CGFloat
        var row: CGFloat
        var searchField: CGFloat
        var tabButton: CGFloat
        var pickerRow: CGFloat
        var shortcutRecordField: CGFloat
        var keyBadge: CGFloat
        var gauge: CGFloat

        static let `default` = CornerRadii(
            panel: 14, contentArea: 12, card: 10, tabBar: 10,
            row: 8, searchField: 8, tabButton: 8,
            pickerRow: 6, shortcutRecordField: 6, keyBadge: 3, gauge: 1
        )

        init(
            panel: CGFloat = Self.default.panel, contentArea: CGFloat = Self.default.contentArea,
            card: CGFloat = Self.default.card, tabBar: CGFloat = Self.default.tabBar,
            row: CGFloat = Self.default.row, searchField: CGFloat = Self.default.searchField,
            tabButton: CGFloat = Self.default.tabButton, pickerRow: CGFloat = Self.default.pickerRow,
            shortcutRecordField: CGFloat = Self.default.shortcutRecordField,
            keyBadge: CGFloat = Self.default.keyBadge, gauge: CGFloat = Self.default.gauge
        ) {
            self.panel = panel; self.contentArea = contentArea; self.card = card
            self.tabBar = tabBar; self.row = row; self.searchField = searchField
            self.tabButton = tabButton; self.pickerRow = pickerRow
            self.shortcutRecordField = shortcutRecordField
            self.keyBadge = keyBadge; self.gauge = gauge
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let d = Self.default
            panel = try container.decodeIfPresent(CGFloat.self, forKey: .panel) ?? d.panel
            contentArea = try container.decodeIfPresent(CGFloat.self, forKey: .contentArea) ?? d.contentArea
            card = try container.decodeIfPresent(CGFloat.self, forKey: .card) ?? d.card
            tabBar = try container.decodeIfPresent(CGFloat.self, forKey: .tabBar) ?? d.tabBar
            row = try container.decodeIfPresent(CGFloat.self, forKey: .row) ?? d.row
            searchField = try container.decodeIfPresent(CGFloat.self, forKey: .searchField) ?? d.searchField
            tabButton = try container.decodeIfPresent(CGFloat.self, forKey: .tabButton) ?? d.tabButton
            pickerRow = try container.decodeIfPresent(CGFloat.self, forKey: .pickerRow) ?? d.pickerRow
            shortcutRecordField = try container.decodeIfPresent(CGFloat.self, forKey: .shortcutRecordField) ?? d.shortcutRecordField
            keyBadge = try container.decodeIfPresent(CGFloat.self, forKey: .keyBadge) ?? d.keyBadge
            gauge = try container.decodeIfPresent(CGFloat.self, forKey: .gauge) ?? d.gauge
        }
    }

    struct Spacing: Codable, Sendable, Equatable {
        var panelPadding: CGFloat
        var sectionSpacing: CGFloat
        var rowHorizontalPadding: CGFloat
        var rowVerticalPadding: CGFloat
        var contentAreaPadding: CGFloat
        var rowSpacing: CGFloat
        var rowDetailsSpacing: CGFloat
        var separatorThickness: CGFloat

        static let `default` = Spacing(
            panelPadding: 12, sectionSpacing: 12,
            rowHorizontalPadding: 8, rowVerticalPadding: 8,
            contentAreaPadding: 10, rowSpacing: 2,
            rowDetailsSpacing: 3,
            separatorThickness: 3
        )

        init(
            panelPadding: CGFloat = Self.default.panelPadding,
            sectionSpacing: CGFloat = Self.default.sectionSpacing,
            rowHorizontalPadding: CGFloat = Self.default.rowHorizontalPadding,
            rowVerticalPadding: CGFloat = Self.default.rowVerticalPadding,
            contentAreaPadding: CGFloat = Self.default.contentAreaPadding,
            rowSpacing: CGFloat = Self.default.rowSpacing,
            rowDetailsSpacing: CGFloat = Self.default.rowDetailsSpacing,
            separatorThickness: CGFloat = Self.default.separatorThickness
        ) {
            self.panelPadding = panelPadding; self.sectionSpacing = sectionSpacing
            self.rowHorizontalPadding = rowHorizontalPadding; self.rowVerticalPadding = rowVerticalPadding
            self.contentAreaPadding = contentAreaPadding; self.rowSpacing = rowSpacing
            self.rowDetailsSpacing = rowDetailsSpacing; self.separatorThickness = separatorThickness
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let d = Self.default
            panelPadding = try container.decodeIfPresent(CGFloat.self, forKey: .panelPadding) ?? d.panelPadding
            sectionSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .sectionSpacing) ?? d.sectionSpacing
            rowHorizontalPadding = try container.decodeIfPresent(CGFloat.self, forKey: .rowHorizontalPadding) ?? d.rowHorizontalPadding
            rowVerticalPadding = try container.decodeIfPresent(CGFloat.self, forKey: .rowVerticalPadding) ?? d.rowVerticalPadding
            contentAreaPadding = try container.decodeIfPresent(CGFloat.self, forKey: .contentAreaPadding) ?? d.contentAreaPadding
            rowSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .rowSpacing) ?? d.rowSpacing
            rowDetailsSpacing = try container.decodeIfPresent(CGFloat.self, forKey: .rowDetailsSpacing) ?? d.rowDetailsSpacing
            separatorThickness = try container.decodeIfPresent(CGFloat.self, forKey: .separatorThickness) ?? d.separatorThickness
        }
    }

    struct FontSpec: Codable, Sendable, Equatable {
        /// PostScript / family name. `nil` = use the system font.
        var family: String?
        /// Point size. `nil` = keep the built-in default.
        var size: Double?
        /// Weight string: `"regular"`, `"medium"`, `"semibold"`, `"bold"`. `nil` = built-in default.
        var weight: String?

        static let `default` = FontSpec()

        init(family: String? = nil, size: Double? = nil, weight: String? = nil) {
            self.family = family
            self.size = size
            self.weight = weight
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            family = try container.decodeIfPresent(String.self, forKey: .family)
            size   = try container.decodeIfPresent(Double.self, forKey: .size)
            weight = try container.decodeIfPresent(String.self, forKey: .weight)
        }
    }

    struct Fonts: Codable, Sendable, Equatable {
        /// Font for regular (non-monospace) clipboard rows.
        var row: FontSpec
        /// Font for monospace clipboard rows (items copied from terminals / IDEs).
        var rowMono: FontSpec

        static let `default` = Fonts(row: .default, rowMono: .default)

        init(row: FontSpec = .default, rowMono: FontSpec = .default) {
            self.row = row
            self.rowMono = rowMono
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            row     = try container.decodeIfPresent(FontSpec.self, forKey: .row)     ?? .default
            rowMono = try container.decodeIfPresent(FontSpec.self, forKey: .rowMono) ?? .default
        }
    }

    // MARK: - Default + Built-in Themes

    static let `default` = Theme(
        id: "default",
        name: "Default",
        options: Options(overlayBlurRadius: 1),
        fills: Fills(
            rowSelected: ThemeFill(opacity: 0.30)
        ),
        colors: Colors(
            searchHighlightBackground: "#007AFF", searchHighlightBackgroundOpacity: 0
        ),
        effects: Effects(
            searchHighlightTextGlow: ThemeGlow(color: "#0096FF", radius: 8, opacity: 0.8)
        )
    )

    static let rose = Theme(
        id: "rose",
        name: "Rose",
        options: Options(useMaterial: false, useSystemAccent: false, overlayBlurRadius: 1),
        fills: Fills(
            panel: .solid("#4B3943", opacity: 0.98),
            contentArea: .solid("#2A2025", opacity: 0.84),
            tabBar: .solid("#2F262C", opacity: 0.78),
            rowSelected: .solid("#E8A0BF", opacity: 0.16), rowHovered: .solid("#E8A0BF", opacity: 0.07),
            card: .solid("#231C20", opacity: 0.6), overlay: .solid("#1A1418", opacity: 0.5)
        ),
        colors: Colors(
            accent: "#E8A0BF",
            pillBackground: "#C4909A", pillBackgroundOpacity: 0.14,
            shortcutKeyBackground: "#3A2A30", shortcutKeyBackgroundOpacity: 0.5,
            cardStroke: "#E8A0BF", cardStrokeOpacity: 0.08,
            imageIndicator: "#F0C987", statusReady: "#A8D8A8", statusWarning: "#F0C987",
            gaugeUnfilled: "#8A7580", gaugeUnfilledOpacity: 0.15,
            searchHighlight: "#FAACCE", searchHighlightBackground: "#E8A0BF", searchHighlightBackgroundOpacity: 0
        )
    )

    static let nord = Theme(
        id: "nord",
        name: "Nord",
        options: Options(useMaterial: false, useSystemAccent: false, overlayBlurRadius: 1),
        fills: Fills(
            panel: .solid("#475164", opacity: 1.0),
            contentArea: .solid("#2E3440"),
            tabBar: .solid("#272C36", opacity: 0.6),
            rowSelected: .solid("#88C0D0", opacity: 0.16), rowHovered: .solid("#88C0D0", opacity: 0.07),
            card: .solid("#272C36", opacity: 0.6), overlay: .solid("#1D2128", opacity: 0.55)
        ),
        colors: Colors(
            accent: "#88C0D0",
            pillBackground: "#7B88A0", pillBackgroundOpacity: 0.14,
            shortcutKeyBackground: "#272C36", shortcutKeyBackgroundOpacity: 0.5,
            cardStroke: "#88C0D0", cardStrokeOpacity: 0.06,
            imageIndicator: "#EBCB8B", statusReady: "#A3BE8C", statusWarning: "#EBCB8B",
            gaugeUnfilled: "#616E88", gaugeUnfilledOpacity: 0.2,
            searchHighlight: "#AEE35F", searchHighlightBackground: "#88C0D0", searchHighlightBackgroundOpacity: 0
        ),
        effects: Effects(
            searchHighlightTextGlow: ThemeGlow(color: "#AEE35F", radius: 5, opacity: 0.67)
        ),
        cornerRadii: CornerRadii(
            panel: 12, contentArea: 10, card: 8, tabBar: 8,
            row: 6, searchField: 6, tabButton: 6,
            pickerRow: 5, shortcutRecordField: 5, keyBadge: 3, gauge: 1
        )
    )

    static let neonNoir = Theme(
        id: "neon-noir",
        name: "Neon Noir",
        options: Options(useMaterial: false, useSystemAccent: false, overlayBlurRadius: 1),
        fills: Fills(
            panel: .linearGradient(["#0D0D12", "#080810"], from: "top", to: "bottom", opacity: 0.95),
            contentArea: .linearGradient(["#0D0D12", "#080810"], from: "top", to: "bottom", opacity: 0.95),
            tabBar: .solid("#08080C", opacity: 0.7),
            tabButtonSelected: .solid("#FF2D6F", opacity: 0.40),
            rowSelected: .solid("#FF2D6F", opacity: 0.18),
            rowHovered: .solid("#FF2D6F", opacity: 0.08),
            card: .solid("#08080C", opacity: 0.7),
            overlay: .solid("#000000", opacity: 0.65)
        ),
        colors: Colors(
            accent: "#FF2D6F",
            pillBackground: "#FF2D6F", pillBackgroundOpacity: 0.12,
            shortcutKeyBackground: "#FF2D6F", shortcutKeyBackgroundOpacity: 0.08,
            cardStroke: "#FF2D6F", cardStrokeOpacity: 0.12,
            imageIndicator: "#00E5FF", statusReady: "#00E676", statusWarning: "#FFD600",
            gaugeUnfilled: "#FF2D6F", gaugeUnfilledOpacity: 0.1
        ),
        borders: Borders(
            panel: ThemeBorder(color: "#FF2D6F", width: 1, opacity: 0.25),
            selectedRow: ThemeBorder(color: "#FF2D6F", width: 1, opacity: 0.5, animation: "sweep")
        ),
        effects: Effects(
            selectedRowGlow: ThemeGlow(color: "#FF2D6F", radius: 14, opacity: 0.3, innerRadius: 3, innerOpacity: 0.85),
            hoveredRowGlow: ThemeGlow(color: "#FF2D6F", radius: 7, opacity: 0.15, innerRadius: 2, innerOpacity: 0.5)
        ),
        cornerRadii: CornerRadii(
            panel: 10, contentArea: 8, card: 6, tabBar: 6,
            row: 4, searchField: 4, tabButton: 4,
            pickerRow: 3, shortcutRecordField: 3, keyBadge: 2, gauge: 1
        ),
        spacing: Spacing(
            panelPadding: 10, sectionSpacing: 10,
            rowHorizontalPadding: 8, rowVerticalPadding: 6,
            contentAreaPadding: 8, rowSpacing: 1
        )
    )

    static let vapor = Theme(
        id: "vapor",
        name: "Vapor",
        options: Options(useMaterial: false, useSystemAccent: false, animatedPanel: true, overlayBlurRadius: 1),
        fills: Fills(
            panel: .linearGradient(["#1A1028", "#220E38"], from: "top", to: "bottom", opacity: 0.95),
            contentArea: .linearGradient(["#1A1028", "#220E38"], from: "top", to: "bottom", opacity: 0.95),
            tabBar: .solid("#140C22", opacity: 0.6),
            tabButtonSelected: .linearGradient(["#FF71CE", "#B967FF"], from: "leading", to: "trailing", opacity: 0.3),
            rowSelected: .linearGradient(["#FF71CE", "#B967FF"], from: "leading", to: "trailing", opacity: 0.09),
            rowHovered: .solid("#B967FF", opacity: 0.1),
            card: .solid("#140C22", opacity: 0.6),
            overlay: .solid("#0D0818", opacity: 0.6)
        ),
        colors: Colors(
            accent: "#FF71CE",
            pillBackground: "#B967FF", pillBackgroundOpacity: 0.14,
            shortcutKeyBackground: "#B967FF", shortcutKeyBackgroundOpacity: 0.08,
            cardStroke: "#B967FF", cardStrokeOpacity: 0.1,
            imageIndicator: "#05FFA1", statusReady: "#05FFA1", statusWarning: "#FFFB96",
            gaugeUnfilled: "#B967FF", gaugeUnfilledOpacity: 0.12,
            searchHighlight: "#E465BA"
        ),
        effects: Effects(
            selectedRowGlow: ThemeGlow(color: "#FF71CE", radius: 8, opacity: 0.19, innerRadius: 3, innerOpacity: 0.75),
            hoveredRowGlow: ThemeGlow(color: "#44265F", radius: 4, opacity: 0.2, innerRadius: 2, innerOpacity: 0.5),
            panelGlow: ThemeGlow(color: "#B967FF", radius: 12, opacity: 0.15),
            searchHighlightTextGlow: ThemeGlow(color: "#FF71CE", radius: 5, opacity: 0.66)
        ),
        cornerRadii: CornerRadii(
            panel: 16, contentArea: 14, card: 12, tabBar: 12,
            row: 10, searchField: 10, tabButton: 10,
            pickerRow: 8, shortcutRecordField: 8, keyBadge: 4, gauge: 2
        )
    )

    static let macOSLight = Theme(
        id: "macos-light",
        name: "macOS Light",
        options: Options(useMaterial: true, useSystemAccent: true, appearance: "light", overlayBlurRadius: 1),
        fills: Fills(
            panel: ThemeFill(opacity: 0),
            contentArea: ThemeFill(opacity: 0),
            tabButtonSelected: .solid("#FFFFFF", opacity: 0.5),
            rowSelected: .solid("#929292", opacity: 0.84),
            rowHovered: ThemeFill(opacity: 0.06),
            card: .solid("#000000", opacity: 0.04),
            overlay: .solid("#000000", opacity: 0.12)
        ),
        colors: Colors(
            accent: "#007AFF",
            pillBackgroundOpacity: 0.08,
            shortcutKeyBackground: "#000000", shortcutKeyBackgroundOpacity: 0.04,
            cardStroke: "#000000", cardStrokeOpacity: 0.06,
            imageIndicator: "#FF9500",
            statusReady: "#34C759", statusWarning: "#FF9500",
            gaugeUnfilledOpacity: 0.1,
            searchHighlight: "#0096FF"
        ),
        borders: Borders(
            selectedRow: ThemeBorder(color: "#000000", width: 1, opacity: 0.3)
        )
    )

    static let sciFi = Theme(
        id: "sci-fi",
        name: "Sci-Fi",
        options: Options(useMaterial: false, useSystemAccent: false, overlayBlurRadius: 1),
        fills: Fills(
            panel: .linearGradient(["#2F2F2F", "#12100A"], from: "top", to: "bottom", opacity: 0.98),
            contentArea: .linearGradient(["#2F2F2F", "#12100A"], from: "top", to: "bottom", opacity: 0.98),
            tabBar: .solid("#0A0800", opacity: 0.45),
            tabButtonSelected: .solid("#FF6A00", opacity: 0.29),
            rowSelected: .solid("#FF6A00", opacity: 0.14),
            rowHovered: .solid("#FF6A00", opacity: 0.06),
            card: .solid("#AAAAAA", opacity: 0.1),
            overlay: .solid("#000000", opacity: 0.6)
        ),
        colors: Colors(
            accent: "#FF6A00",
            pillBackground: "#FF6A00", pillBackgroundOpacity: 0.1,
            shortcutKeyBackground: "#FF6A00", shortcutKeyBackgroundOpacity: 0.06,
            cardStroke: "#FF6A00", cardStrokeOpacity: 0.1,
            imageIndicator: "#4DEEEA",
            statusReady: "#00FF00", statusWarning: "#FF6A00",
            gaugeUnfilled: "#FF6A00", gaugeUnfilledOpacity: 0.08
        ),
        borders: Borders(
            panel: ThemeBorder(color: "#000000", width: 1, opacity: 0.5),
            contentArea: ThemeBorder(color: "#FF6A00", width: 1, opacity: 0.08),
            selectedRow: ThemeBorder(color: "#FF6A00", width: 1, opacity: 0.4, animation: "flash"),
            card: ThemeBorder(color: "#000000", width: 1, opacity: 0.12)
        ),
        effects: Effects(
            selectedRowGlow: ThemeGlow(color: "#FF6A00", radius: 10, opacity: 0.25, innerRadius: 3, innerOpacity: 0.75),
            hoveredRowGlow: ThemeGlow(color: "#FF6A00", radius: 5, opacity: 0.12, innerRadius: 2, innerOpacity: 0.4),
            panelGlow: ThemeGlow(color: "#FF6A00", radius: 10, opacity: 0.08)
        ),
        cornerRadii: CornerRadii(
            panel: 8, contentArea: 6, card: 4, tabBar: 6,
            row: 3, searchField: 3, tabButton: 4,
            pickerRow: 2, shortcutRecordField: 2, keyBadge: 2, gauge: 1
        ),
        spacing: Spacing(
            panelPadding: 10, sectionSpacing: 10,
            rowHorizontalPadding: 8, rowVerticalPadding: 6,
            contentAreaPadding: 8, rowSpacing: 1
        )
    )

    static let space = Theme(
        id: "space",
        name: "Space",
        options: Options(useMaterial: true, useSystemAccent: true),
        fills: Fills(
            panel: ThemeFill(opacity: 0),
            contentArea: .solid("#000000", opacity: 0.7),
            tabBar: .solid("#1E1E1E", opacity: 0.85),
            tabButtonSelected: .solid("#FFFFFF", opacity: 0.27),
            rowSelected: ThemeFill(opacity: 0.18),
            rowHovered: ThemeFill(opacity: 0.09),
            card: .solid("#000000", opacity: 0.15),
            overlay: .solid("#000000", opacity: 0.15)
        ),
        colors: Colors(searchHighlight: "#FFCC00"),
        borders: Borders(
            selectedRow: ThemeBorder(color: "#FFFFFF", width: 1, opacity: 0.4, dash: [6, 1])
        ),
        effects: Effects(
            selectedRowGlow: ThemeGlow(color: "#FF6A00", radius: 6, opacity: 0.8),
            hoveredRowGlow: ThemeGlow(color: "#9D457A", radius: 5, opacity: 1.0),
            searchHighlightTextGlow: ThemeGlow(color: "#FFCC00", radius: 5, opacity: 0.8)
        ),
        cornerRadii: CornerRadii(
            panel: 14, contentArea: 12, card: 10, tabBar: 10,
            row: 8, searchField: 8, tabButton: 8,
            pickerRow: 6, shortcutRecordField: 6, keyBadge: 3, gauge: 1
        ),
        spacing: Spacing(
            panelPadding: 10, sectionSpacing: 10,
            rowHorizontalPadding: 8, rowVerticalPadding: 6,
            contentAreaPadding: 8, rowSpacing: 1
        )
    )

    static let deepSpace = Theme(
        id: "deep-space",
        name: "Deep Space",
        options: Options(useMaterial: false, useSystemAccent: true, overlayBlurRadius: 1),
        fills: Fills(
            panel: .meshGradient(
                ["#200010", "#100030", "#001020",
                 "#280020", "#0C1840", "#003030",
                 "#100010", "#080C28", "#041818"],
                columns: 3, rows: 3, opacity: 0.95
            ),
            contentArea: .meshGradient(
                ["#200010", "#100030", "#001020",
                 "#280020", "#0C1840", "#003030",
                 "#100010", "#080C28", "#041818"],
                columns: 3, rows: 3, opacity: 0.95
            ),
            tabBar: .solid("#000000", opacity: 0.05),
            tabButtonSelected: .solid("#FFFFFF", opacity: 0.1),
            rowSelected: ThemeFill(opacity: 0.18),
            rowHovered: ThemeFill(opacity: 0.09),
            card: .solid("#000000", opacity: 0.15),
            overlay: .solid("#000000", opacity: 0.15)
        ),
        colors: Colors(
            searchHighlight: "#FFFB00",
            searchHighlightBackground: "#FFFFFF", searchHighlightBackgroundOpacity: 0
        ),
        borders: Borders(
            selectedRow: ThemeBorder(color: "#FFFFFF", width: 1, opacity: 0.4, dash: [6, 1])
        ),
        effects: Effects(
            selectedRowGlow: ThemeGlow(color: "#FF6A00", radius: 6, opacity: 0.8),
            hoveredRowGlow: ThemeGlow(color: "#FF0000", radius: 5, opacity: 1.0),
            searchHighlightTextGlow: ThemeGlow(color: "#FFFB00", radius: 4, opacity: 0.89)
        ),
        spacing: Spacing(
            panelPadding: 10, sectionSpacing: 10,
            rowHorizontalPadding: 8, rowVerticalPadding: 6,
            contentAreaPadding: 8, rowSpacing: 1
        )
    )

    static let metal = Theme(
        id: "metal",
        name: "Metal",
        options: Options(material: "ultraThin", useSystemAccent: true, overlayBlurRadius: 1),
        fills: Fills(
            panel: .solid("#797979", opacity: 0.80),
            contentArea: .solid("#1E1E1E", opacity: 0.84),
            tabBar: .solid("#797979", opacity: 0.89),
            tabButtonSelected: .solid("#000000", opacity: 0.74),
            rowSelected: .solid("#FFFFFF", opacity: 0),
            rowHovered: .solid("#C0C0C0", opacity: 0.14),
            card: .solid("#000000", opacity: 0.15),
            overlay: .solid("#000000", opacity: 0.46)
        ),
        colors: Colors(
            pillBackground: "#FFFFFF", pillBackgroundOpacity: 0.11,
            searchHighlight: "#FFCC00",
            separator: "#FFFFFF", separatorOpacity: 0.3
        ),
        borders: Borders(
            contentArea: ThemeBorder(color: "#FFFFFF", width: 1, opacity: 0.30),
            selectedRow: ThemeBorder(color: "#FFFFFF", width: 1, opacity: 0.4, dash: [6, 1], animation: "flash"),
            tabBar: ThemeBorder(color: "#FFFFFF", width: 1, opacity: 0.2)
        ),
        effects: Effects(
            selectedRowGlow: ThemeGlow(color: "#FF0000", radius: 4, opacity: 1.0, innerRadius: 1.5, innerOpacity: 0.40),
            hoveredRowGlow: ThemeGlow(color: "#C0C0C0", radius: 5, opacity: 0.76),
            searchHighlightTextGlow: ThemeGlow(color: "#FFCC00", radius: 5, opacity: 0.8),
            tabBarInnerShadow: ThemeInnerShadow(color: "#000000", radius: 1, opacity: 0.7, x: 1, y: 1),
            contentAreaInnerShadow: ThemeInnerShadow(color: "#000000", radius: 1, opacity: 0.6, x: 1, y: 1)
        ),
        spacing: Spacing(
            panelPadding: 10, sectionSpacing: 10,
            rowHorizontalPadding: 8, rowVerticalPadding: 6,
            contentAreaPadding: 8, rowSpacing: 1
        ),
        fonts: Fonts(rowMono: FontSpec(family: "InconsolataGo Nerd Font", size: 13, weight: "regular"))
    )

    static let nasaColor = Theme(
        id: "future-color",
        name: "Future Color",
        options: Options(material: "regular", useSystemAccent: true),
        fills: Fills(
            panel: .meshGradient(
                ["#200010", "#100030", "#001020",
                 "#280020", "#0C1840", "#003030",
                 "#100010", "#080C28", "#041818"],
                columns: 3, rows: 3
            ),
            contentArea: .meshGradient(
                ["#200010", "#100030", "#001020",
                 "#280020", "#0C1840", "#003030",
                 "#100010", "#080C28", "#041818"],
                columns: 3, rows: 3
            ),
            tabBar: .solid("#777777", opacity: 0.3),
            tabButtonSelected: .solid("#222222", opacity: 0.9),
            rowSelected: ThemeFill(opacity: 0.18),
            rowHovered: ThemeFill(opacity: 0.09),
            card: .solid("#000000", opacity: 0.15),
            overlay: .solid("#000000", opacity: 0.15)
        ),
        colors: Colors(searchHighlight: "#FFCC00"),
        borders: Borders(
            selectedRow: ThemeBorder(color: "#FFFFFF", width: 1, opacity: 0.4, dash: [6, 1], animation: "flash")
        ),
        effects: Effects(
            selectedRowGlow: ThemeGlow(color: "#FF6A00", radius: 10, opacity: 0.4, innerRadius: 3, innerOpacity: 0.85),
            hoveredRowGlow: ThemeGlow(color: "#7C9AA7", radius: 8, opacity: 0.3, innerRadius: 2, innerOpacity: 0.6)
        ),
        spacing: Spacing(
            panelPadding: 10, sectionSpacing: 10,
            rowHorizontalPadding: 8, rowVerticalPadding: 6,
            contentAreaPadding: 8, rowSpacing: 1
        )
    )

    static let nasa = Theme(
        id: "future-blue",
        name: "Future Blue",
        options: Options(
            material: "none",
            useSystemAccent: true,
            animatedPanelColor: "#FFFFFF",
            animatedPanelPeriod: 10.0,
            overlayBlurRadius: 1
        ),
        fills: Fills(
            panel: .solid("#5E5E5E", opacity: 1.0),
            contentArea: .solid("#000000", opacity: 0.70),
            tabBar: .solid("#1E1E1E", opacity: 0.85),
            tabButtonSelected: .solid("#FFFFFF", opacity: 0.27),
            rowSelected: ThemeFill(opacity: 0),
            rowHovered: .solid("#C0C0C0", opacity: 0),
            card: .solid("#000000", opacity: 0.15),
            overlay: .solid("#000000", opacity: 0.45)
        ),
        colors: Colors(
            pillBackground: "#FFFFFF",
            gaugeUnfilled: "#FFFFFF",
            searchHighlight: "#FFCC00"
        ),
        borders: Borders(
            selectedRow: ThemeBorder(color: "#FFFFFF", width: 1, opacity: 0.4, dash: [6, 1], animation: "flash")
        ),
        effects: Effects(
            selectedRowGlow: ThemeGlow(color: "#0096FF", radius: 10, opacity: 0.4, innerRadius: 3, innerOpacity: 0.85),
            hoveredRowGlow: ThemeGlow(color: "#C0C0C0", radius: 8, opacity: 0.05, innerRadius: 2, innerOpacity: 0.37),
            selectedRowTextGlow: ThemeGlow(color: "#FFFFFF", radius: 6, opacity: 0.4),
            searchHighlightTextGlow: ThemeGlow(color: "#FFCC00", radius: 5, opacity: 0.8),
            separatorGlow: ThemeGlow(color: "#EEEEFF", radius: 2, opacity: 0.05, innerRadius: 1, innerOpacity: 0.1)
        ),
        spacing: Spacing(
            panelPadding: 10, sectionSpacing: 10,
            rowHorizontalPadding: 8, rowVerticalPadding: 6,
            contentAreaPadding: 8, rowSpacing: 1,
            separatorThickness: 5
        )
    )

    static let builtInThemes: [Theme] = [
        .default, .macOSLight, .rose, .nord, .neonNoir, .sciFi, .space, .deepSpace, .vapor, .metal, .nasaColor, .nasa,
    ]

    // MARK: - Initializers

    init(
        id: String = Self.default.id,
        name: String = Self.default.name,
        options: Options = .default,
        fills: Fills = .default,
        colors: Colors = .default,
        borders: Borders = .default,
        effects: Effects = .default,
        cornerRadii: CornerRadii = .default,
        spacing: Spacing = .default,
        fonts: Fonts = .default
    ) {
        self.id = id; self.name = name; self.options = options
        self.fills = fills; self.colors = colors
        self.borders = borders; self.effects = effects
        self.cornerRadii = cornerRadii; self.spacing = spacing
        self.fonts = fonts
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        options = try container.decodeIfPresent(Options.self, forKey: .options) ?? .default
        fills = try container.decodeIfPresent(Fills.self, forKey: .fills) ?? .default
        colors = try container.decodeIfPresent(Colors.self, forKey: .colors) ?? .default
        borders = try container.decodeIfPresent(Borders.self, forKey: .borders) ?? .default
        effects = try container.decodeIfPresent(Effects.self, forKey: .effects) ?? .default
        cornerRadii = try container.decodeIfPresent(CornerRadii.self, forKey: .cornerRadii) ?? .default
        spacing = try container.decodeIfPresent(Spacing.self, forKey: .spacing) ?? .default
        fonts = try container.decodeIfPresent(Fonts.self, forKey: .fonts) ?? .default
    }
}

// MARK: - Resolved Font Accessors

extension Theme {
    private func resolvedFont(_ spec: FontSpec, defaultSize: Double, defaultWeight: Font.Weight, defaultDesign: Font.Design) -> Font {
        let size = spec.size ?? defaultSize
        let weight: Font.Weight = switch spec.weight {
        case "medium":   .medium
        case "semibold": .semibold
        case "bold":     .bold
        default:         defaultWeight
        }
        if let family = spec.family, !family.isEmpty {
            return .custom(family, size: size).weight(weight)
        }
        return .system(size: size, weight: weight, design: defaultDesign)
    }

    /// Font for regular (non-monospace) row text.
    var resolvedRowFont: Font {
        resolvedFont(fonts.row, defaultSize: 13, defaultWeight: .regular, defaultDesign: .default)
    }

    /// Font for monospace row text (items from terminals / IDEs).
    var resolvedRowMonoFont: Font {
        resolvedFont(fonts.rowMono, defaultSize: 12, defaultWeight: .regular, defaultDesign: .monospaced)
    }
}

// MARK: - Hex Color Parsing

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.hasPrefix("#") { cleaned.removeFirst() }

        var rgb: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&rgb) else { return nil }

        switch cleaned.count {
        case 6:
            self.init(
                red: Double((rgb >> 16) & 0xFF) / 255.0,
                green: Double((rgb >> 8) & 0xFF) / 255.0,
                blue: Double(rgb & 0xFF) / 255.0
            )
        case 8:
            self.init(
                red: Double((rgb >> 24) & 0xFF) / 255.0,
                green: Double((rgb >> 16) & 0xFF) / 255.0,
                blue: Double((rgb >> 8) & 0xFF) / 255.0,
                opacity: Double(rgb & 0xFF) / 255.0
            )
        default:
            return nil
        }
    }
}

// MARK: - Appearance

extension Theme {
    var colorScheme: ColorScheme? {
        switch options.appearance {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

// MARK: - Resolved Fill Accessors

extension Theme {
    var resolvedPanelFill: AnyShapeStyle {
        fills.panel.resolved(fallback: Color(nsColor: .controlBackgroundColor), defaultOpacity: Fills.panelDefaultOpacity)
    }

    var resolvedContentAreaFill: AnyShapeStyle {
        fills.contentArea.resolved(fallback: Color(nsColor: .controlBackgroundColor), defaultOpacity: Fills.panelDefaultOpacity)
    }

    var resolvedTabBarFill: AnyShapeStyle {
        fills.tabBar.resolved(fallback: .black, defaultOpacity: Fills.tabBarDefaultOpacity)
    }

    var resolvedTabButtonSelectedFill: AnyShapeStyle {
        if let fill = fills.tabButtonSelected {
            return fill.resolved(fallback: Color(nsColor: .controlBackgroundColor), defaultOpacity: 1.0)
        }
        return resolvedPanelFill
    }

    var resolvedRowSelectedFill: AnyShapeStyle {
        fills.rowSelected.resolved(fallback: resolvedAccent, defaultOpacity: Fills.rowSelectedDefaultOpacity)
    }

    var resolvedRowHoveredFill: AnyShapeStyle {
        fills.rowHovered.resolved(fallback: resolvedAccent, defaultOpacity: Fills.rowHoveredDefaultOpacity)
    }

    var resolvedCardFill: AnyShapeStyle {
        fills.card.resolved(fallback: .black, defaultOpacity: Fills.cardDefaultOpacity)
    }

    var resolvedOverlayFill: AnyShapeStyle {
        fills.overlay.resolved(fallback: .black, defaultOpacity: Fills.overlayDefaultOpacity)
    }
}

// MARK: - Resolved Color Accessors

extension Theme {
    var resolvedAccent: Color {
        if options.useSystemAccent { return .accentColor }
        return Color(hex: colors.accent) ?? .accentColor
    }

    var resolvedPillBackground: Color {
        let base = Color(hex: colors.pillBackground) ?? .secondary
        return base.opacity(colors.pillBackgroundOpacity ?? 0.12)
    }

    var resolvedShortcutKeyBackground: Color {
        let base = Color(hex: colors.shortcutKeyBackground) ?? .black
        return base.opacity(colors.shortcutKeyBackgroundOpacity ?? 0.06)
    }

    var resolvedCardStroke: Color {
        let base = Color(hex: colors.cardStroke) ?? .white
        return base.opacity(colors.cardStrokeOpacity ?? 0.08)
    }

    var resolvedTextPrimary: Color { Color(hex: colors.textPrimary) ?? .primary }
    var resolvedTextSecondary: Color { Color(hex: colors.textSecondary) ?? .secondary }
    var resolvedTextTertiary: Color { Color(hex: colors.textTertiary) ?? Color(nsColor: .tertiaryLabelColor) }
    var resolvedImageIndicator: Color { Color(hex: colors.imageIndicator) ?? .orange }
    var resolvedStatusReady: Color { Color(hex: colors.statusReady) ?? Color(nsColor: .systemGreen) }
    var resolvedStatusWarning: Color { Color(hex: colors.statusWarning) ?? Color(nsColor: .systemOrange) }

    var resolvedGaugeUnfilled: Color {
        let base = Color(hex: colors.gaugeUnfilled) ?? .secondary
        return base.opacity(colors.gaugeUnfilledOpacity ?? 0.15)
    }

    var resolvedSearchHighlight: Color {
        Color(hex: colors.searchHighlight) ?? resolvedAccent
    }

    var resolvedSearchHighlightBackground: Color? {
        guard let hex = colors.searchHighlightBackground, Color(hex: hex) != nil else { return nil }
        return Color(hex: hex)!.opacity(colors.searchHighlightBackgroundOpacity ?? 0.15)
    }

    var resolvedSeparator: Color {
        let base = Color(hex: colors.separator) ?? resolvedCardStroke
        return base.opacity(colors.separatorOpacity ?? 0.35)
    }

    var resolvedSeparatorThickness: CGFloat {
        spacing.separatorThickness
    }
}

// MARK: - Resolved Border Accessors

extension Theme {
    struct ResolvedBorder {
        let color: Color
        let width: CGFloat
        let dash: [CGFloat]
        let animation: String?
        let animationDuration: Double

        var strokeStyle: StrokeStyle { StrokeStyle(lineWidth: width, dash: dash) }
        var isVisible: Bool { width > 0 }
    }

    func resolvedBorder(_ border: ThemeBorder?, fallbackColor: Color = .clear, fallbackWidth: CGFloat = 0) -> ResolvedBorder {
        guard let border else { return ResolvedBorder(color: fallbackColor, width: fallbackWidth, dash: [], animation: nil, animationDuration: 0.6) }
        let color = (Color(hex: border.color) ?? fallbackColor).opacity(border.opacity ?? 1.0)
        return ResolvedBorder(color: color, width: border.width ?? fallbackWidth, dash: border.dash ?? [], animation: border.animation, animationDuration: border.animationDuration ?? 0.6)
    }

    var resolvedPanelBorder: ResolvedBorder { resolvedBorder(borders.panel) }
    var resolvedContentAreaBorder: ResolvedBorder { resolvedBorder(borders.contentArea) }
    var resolvedSelectedRowBorder: ResolvedBorder { resolvedBorder(borders.selectedRow) }
    var resolvedCardBorder: ResolvedBorder { resolvedBorder(borders.card, fallbackColor: resolvedCardStroke, fallbackWidth: 1) }
    var resolvedSearchFieldBorder: ResolvedBorder { resolvedBorder(borders.searchField) }
    var resolvedTabBarBorder: ResolvedBorder { resolvedBorder(borders.tabBar) }
}

// MARK: - Resolved Glow Accessors

extension Theme {
    struct ResolvedGlow {
        let color: Color
        let radius: CGFloat
        /// Non-nil when a double-glow inner layer is configured.
        let innerColor: Color?
        let innerRadius: CGFloat?
    }

    func resolvedGlow(_ glow: ThemeGlow?) -> ResolvedGlow? {
        guard let glow, let color = Color(hex: glow.color) else { return nil }
        let innerColor: Color? = glow.innerRadius != nil
            ? color.opacity(glow.innerOpacity ?? 0.8)
            : nil
        return ResolvedGlow(
            color: color.opacity(glow.opacity ?? 0.5),
            radius: glow.radius ?? 8,
            innerColor: innerColor,
            innerRadius: glow.innerRadius
        )
    }

    var resolvedSelectedRowGlow: ResolvedGlow? { resolvedGlow(effects.selectedRowGlow) }
    var resolvedHoveredRowGlow: ResolvedGlow? { resolvedGlow(effects.hoveredRowGlow) }
    var resolvedPanelGlow: ResolvedGlow? { resolvedGlow(effects.panelGlow) }
    var resolvedSelectedRowTextGlow: ResolvedGlow? { resolvedGlow(effects.selectedRowTextGlow) }
    var resolvedHoveredRowTextGlow: ResolvedGlow? { resolvedGlow(effects.hoveredRowTextGlow) }
    var resolvedSearchHighlightTextGlow: ResolvedGlow? { resolvedGlow(effects.searchHighlightTextGlow) }
    var resolvedSeparatorGlow: ResolvedGlow? { resolvedGlow(effects.separatorGlow) }
}

// MARK: - Resolved Inner Shadow Accessors

extension Theme {
    struct ResolvedInnerShadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat
    }

    func resolvedInnerShadow(_ shadow: ThemeInnerShadow?) -> ResolvedInnerShadow? {
        guard let shadow else { return nil }
        let base = Color(hex: shadow.color) ?? .black
        return ResolvedInnerShadow(
            color: base.opacity(shadow.opacity ?? 0.4),
            radius: shadow.radius ?? 4,
            x: shadow.x ?? 0,
            y: shadow.y ?? 0
        )
    }

    var resolvedTabBarInnerShadow: ResolvedInnerShadow? { resolvedInnerShadow(effects.tabBarInnerShadow) }
    var resolvedContentAreaInnerShadow: ResolvedInnerShadow? { resolvedInnerShadow(effects.contentAreaInnerShadow) }
}
