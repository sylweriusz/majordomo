import Foundation

extension Bundle {
    /// Resolves a bundled resource without ever touching SwiftPM's `Bundle.module`.
    ///
    /// `Bundle.module`'s generated accessor calls `fatalError` when it can't load the
    /// resource bundle, and it only looks in two places: the `.app` root (where a
    /// bundle would break code signing) and an absolute build-machine path baked in
    /// at compile time. That second path makes the app appear to work on the build
    /// machine while crashing on every other Mac.
    ///
    /// Instead, the packaged `.app` carries its resources in `Contents/Resources`
    /// (found via `Bundle.main`), and a developer `swift run` reads them from the
    /// SwiftPM-generated `Majordomo_Majordomo.bundle` sitting next to the executable.
    /// Neither path can crash.
    static func appResourceURL(forResource name: String, withExtension ext: String) -> URL? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return url
        }
        let spmBundleName = "Majordomo_Majordomo.bundle"
        for base in [Bundle.main.bundleURL, Bundle.main.resourceURL].compactMap({ $0 }) {
            let candidate = base.appendingPathComponent(spmBundleName)
            if let bundle = Bundle(url: candidate),
               let url = bundle.url(forResource: name, withExtension: ext) {
                return url
            }
        }
        return nil
    }
}
