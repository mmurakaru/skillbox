import AppKit
import SwiftUI

/// Bundled provider logos are vector templates rendered white, with no network fetch during launch.
struct ProviderUsageLogo: View {
    let provider: UsageProvider
    /// App bundles keep SPM resources under Contents/Resources so codesigning seals them correctly.
    nonisolated static func logoURL(for provider: UsageProvider, appResourceURL: URL? = Bundle.main.resourceURL) -> URL? {
        if let appResourceURL {
            let bundled = appResourceURL.appendingPathComponent("Skillbox_Skillbox.bundle/ProviderLogos/\(provider.rawValue).pdf")

            if FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        }

        return Bundle.module.url(forResource: provider.rawValue, withExtension: "pdf", subdirectory: "ProviderLogos")
    }

    private var logo: NSImage {
        guard let url = Self.logoURL(for: provider),
            let image = NSImage(contentsOf: url)
        else { return NSImage() }

        return image
    }

    var body: some View {
        Image(nsImage: logo)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(.white)
            .frame(width: 24, height: 24)
            .frame(width: 30, height: 30)
            .accessibilityHidden(true)
    }
}
