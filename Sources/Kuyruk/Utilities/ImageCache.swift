import AppKit
import Foundation

/// Thread-safe image cache with in-memory and optional disk persistence.
/// Used for caching avatar images to eliminate re-downloads.
actor ImageCache {
    // MARK: - Singleton

    static let shared = ImageCache()

    // MARK: - Properties

    private let memoryCache: NSCache<NSString, NSImage>
    private let fileManager: FileManager
    private let cacheDirectory: URL?

    /// Tracks in-flight downloads to avoid duplicate requests
    private var inFlightDownloads: [String: Task<NSImage?, Never>] = [:]

    // MARK: - Initialization

    init() {
        self.memoryCache = NSCache<NSString, NSImage>()
        self.memoryCache.countLimit = 200 // Max 200 images in memory
        self.memoryCache.totalCostLimit = 50 * 1024 * 1024 // 50 MB limit

        self.fileManager = FileManager.default

        // Setup disk cache directory
        if let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let directory = cacheDir.appendingPathComponent("com.kuyruk.imagecache", isDirectory: true)
            self.cacheDirectory = directory
            try? self.fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        } else {
            self.cacheDirectory = nil
        }
    }

    // MARK: - Public Methods

    /// Retrieves an image from cache or downloads it.
    /// - Parameter urlString: The URL string of the image
    /// - Returns: The cached or downloaded image, or nil if failed
    func image(for urlString: String) async -> NSImage? {
        let cacheKey = Self.cacheKey(for: urlString)

        // Check memory cache first
        if let cached = memoryCache.object(forKey: cacheKey as NSString) {
            return cached
        }

        // Check disk cache
        if let diskImage = loadFromDisk(key: cacheKey) {
            self.memoryCache.setObject(diskImage, forKey: cacheKey as NSString)
            return diskImage
        }

        // Check if already downloading
        if let existingTask = inFlightDownloads[cacheKey] {
            return await existingTask.value
        }

        // Download the image
        let downloadTask = Task<NSImage?, Never> {
            await self.downloadImage(urlString: urlString, cacheKey: cacheKey)
        }

        self.inFlightDownloads[cacheKey] = downloadTask
        let result = await downloadTask.value
        self.inFlightDownloads[cacheKey] = nil

        return result
    }

    /// Prefetches images for a list of URLs.
    /// - Parameter urlStrings: Array of URL strings to prefetch
    func prefetch(_ urlStrings: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for urlString in urlStrings.prefix(20) { // Limit concurrent prefetches
                group.addTask {
                    _ = await self.image(for: urlString)
                }
            }
        }
    }

    /// Clears the in-memory cache.
    func clearMemoryCache() {
        self.memoryCache.removeAllObjects()
    }

    /// Clears both memory and disk cache.
    func clearAllCache() {
        self.memoryCache.removeAllObjects()

        if let cacheDir = cacheDirectory {
            try? self.fileManager.removeItem(at: cacheDir)
            try? self.fileManager.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        }
    }

    // MARK: - Private Methods

    private func downloadImage(urlString: String, cacheKey: String) async -> NSImage? {
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = NSImage(data: data) else {
                return nil
            }

            // Cache in memory
            self.memoryCache.setObject(image, forKey: cacheKey as NSString)

            // Save to disk
            self.saveToDisk(data: data, key: cacheKey)

            return image
        } catch {
            DiagnosticsLogger.debug("Image download failed: \(urlString)", category: .network)
            return nil
        }
    }

    private func loadFromDisk(key: String) -> NSImage? {
        guard let cacheDir = cacheDirectory else { return nil }

        let fileURL = cacheDir.appendingPathComponent(key)
        guard let data = try? Data(contentsOf: fileURL) else { return nil }

        return NSImage(data: data)
    }

    nonisolated private func saveToDisk(data: Data, key: String) {
        guard let cacheDir = cacheDirectory else { return }

        let fileURL = cacheDir.appendingPathComponent(key)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func cacheKey(for urlString: String) -> String {
        // Create a filesystem-safe cache key from URL
        let hash = urlString.utf8.reduce(0) { $0 &+ UInt64($1) }
        return String(format: "%016llx", hash)
    }
}
