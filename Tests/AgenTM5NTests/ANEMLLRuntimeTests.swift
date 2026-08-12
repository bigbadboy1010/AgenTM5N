import Foundation
import XCTest
@testable import AgenTM5N

final class ANEMLLRuntimeTests: XCTestCase {
  func testRuntimeConfigurationBoundsGenerationParameters() {
    let configuration = ANEMLLRuntimeConfiguration(
      helperPath: "/tmp/anemllcli",
      metaPath: "/tmp/meta.yaml",
      defaultMaxTokens: 99_999,
      defaultTemperature: 99
    )

    XCTAssertEqual(configuration.defaultMaxTokens, 4_096)
    XCTAssertEqual(configuration.defaultTemperature, 2)
  }

  func testQwenBundleInspectorFindsSplitComponentsAndPrefersLUTHead() throws {
    let root = try makeBundle()
    defer { try? FileManager.default.removeItem(at: root) }

    let descriptor = try ANEMLLModelBundleInspector.inspect(
      metaPath: root.appendingPathComponent("meta.yaml").path
    )

    XCTAssertEqual(descriptor.modelName, "qwen")
    XCTAssertEqual(descriptor.contextLength, 512)
    XCTAssertEqual(descriptor.batchSize, 64)
    XCTAssertEqual(descriptor.ffnURLs.count, 1)
    XCTAssertEqual(descriptor.componentCount, 3)
    XCTAssertEqual(descriptor.lmHeadURL.lastPathComponent, "qwen_lm_head_lut6.mlmodelc")
    XCTAssertEqual(descriptor.embeddingsURL.lastPathComponent, "qwen_embeddings.mlmodelc")
    XCTAssertEqual(descriptor.tokenizerURL.lastPathComponent, "tokenizer.json")
  }

  func testQwenBundleInspectorRejectsMissingTokenizer() throws {
    let root = try makeBundle()
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.removeItem(at: root.appendingPathComponent("tokenizer.json"))

    XCTAssertThrowsError(
      try ANEMLLModelBundleInspector.inspect(
        metaPath: root.appendingPathComponent("meta.yaml").path
      )
    ) { error in
      guard case ANEMLLRuntimeError.invalidModelBundle = error else {
        return XCTFail("Unexpected error: \(error)")
      }
    }
  }

  func testSwiftCLIMetricsParserReadsDecodePrefillTTFTAndTokens() {
    let output = """
    [■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■] 100%
    ✓ Models loaded successfully in 1.55s
    Assistant: hello
    84.4 t/s, TTFT: 15.0ms (1996.9 t/s), 128 tokens [Stop: max_tokens] [Total: 158 tokens]
    """

    let metrics = ANEMLLNativeRuntime.parseMetrics(
      output,
      wallMilliseconds: 1_700
    )

    XCTAssertEqual(metrics.modelLoadSeconds ?? 0, 1.55, accuracy: 0.001)
    XCTAssertEqual(metrics.timeToFirstTokenMilliseconds ?? 0, 15.0, accuracy: 0.001)
    XCTAssertEqual(metrics.prefillTokensPerSecond ?? 0, 1_996.9, accuracy: 0.001)
    XCTAssertEqual(metrics.inferenceTokensPerSecond ?? 0, 84.4, accuracy: 0.001)
    XCTAssertEqual(metrics.generatedTokens, 128)
    XCTAssertEqual(metrics.totalTokens, 158)
    XCTAssertEqual(metrics.stopReason, "max_tokens")
    XCTAssertEqual(metrics.chatMetrics.promptTokens, 30)
    XCTAssertEqual(metrics.chatMetrics.generatedTokens, 128)
  }

  private func makeBundle() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("AgenTM5N-ANEMLL-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )

    try """
    model_prefix: qwen
    context_length: 512
    batch_size: 64
    """.write(
      to: root.appendingPathComponent("meta.yaml"),
      atomically: true,
      encoding: .utf8
    )
    try "{}".write(
      to: root.appendingPathComponent("tokenizer.json"),
      atomically: true,
      encoding: .utf8
    )
    try "{}".write(
      to: root.appendingPathComponent("tokenizer_config.json"),
      atomically: true,
      encoding: .utf8
    )

    for name in [
      "qwen_embeddings.mlmodelc",
      "qwen_FFN_PF_lut6_chunk_01of01.mlmodelc",
      "qwen_lm_head.mlmodelc",
      "qwen_lm_head_lut6.mlmodelc",
    ] {
      try FileManager.default.createDirectory(
        at: root.appendingPathComponent(name, isDirectory: true),
        withIntermediateDirectories: true
      )
    }

    return root
  }
}
