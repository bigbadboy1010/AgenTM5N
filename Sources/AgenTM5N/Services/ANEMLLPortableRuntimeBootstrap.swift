import Foundation

public enum ANEMLLPortableRuntimeBootstrap {
  public static func configureBundledRuntimeIfNeeded() {
    let manager = FileManager.default
    let current = ANEMLLRuntimeStore.load()

    let currentHelper = ANEMLLRuntimeStore.expanded(current.helperPath)
    let currentMeta = ANEMLLRuntimeStore.expanded(current.metaPath)
    let currentHelperValid = manager.isExecutableFile(atPath: currentHelper)
    let currentMetaValid = manager.fileExists(atPath: currentMeta)

    guard !currentHelperValid || !currentMetaValid else {
      return
    }

    guard
      let contentsURL = Bundle.main.executableURL?
        .deletingLastPathComponent()
        .deletingLastPathComponent(),
      let resourcesURL = Bundle.main.resourceURL
    else {
      return
    }

    let bundledHelper = contentsURL
      .appendingPathComponent("Helpers/ANEMLL/anemllcli", isDirectory: false)
    let bundledMeta = resourcesURL
      .appendingPathComponent("Models/ANEMLL/Qwen3/meta.yaml", isDirectory: false)

    guard manager.isExecutableFile(atPath: bundledHelper.path) else {
      return
    }
    guard manager.fileExists(atPath: bundledMeta.path) else {
      return
    }

    do {
      _ = try ANEMLLModelBundleInspector.inspect(metaPath: bundledMeta.path)
    } catch {
      AppLogger.app.error(
        "Bundled ANEMLL model validation failed: \(error.localizedDescription, privacy: .public)"
      )
      return
    }

    let bundled = ANEMLLRuntimeConfiguration(
      helperPath: bundledHelper.path,
      metaPath: bundledMeta.path,
      defaultMaxTokens: current.defaultMaxTokens,
      defaultTemperature: current.defaultTemperature
    )
    ANEMLLRuntimeStore.save(bundled)

    AppLogger.app.info(
      "Portable ANEMLL runtime configured from application bundle."
    )
  }
}
