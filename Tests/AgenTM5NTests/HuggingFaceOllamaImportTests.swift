import XCTest
@testable import AgenTM5N

final class HuggingFaceOllamaImportTests: XCTestCase {
  func testNormalizesShortRepositoryReference() throws {
    let reference = try HuggingFaceOllamaReference(
      "bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M"
    )

    XCTAssertEqual(
      reference.modelIdentifier,
      "hf.co/bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M"
    )
  }

  func testNormalizesFullHuggingFaceURL() throws {
    let reference = try HuggingFaceOllamaReference(
      "https://huggingface.co/unsloth/gpt-oss-20b-GGUF"
    )

    XCTAssertEqual(
      reference.modelIdentifier,
      "hf.co/unsloth/gpt-oss-20b-GGUF"
    )
    XCTAssertEqual(reference.displayName, "unsloth/gpt-oss-20b-GGUF")
  }

  func testPreservesCanonicalHFReference() throws {
    let reference = try HuggingFaceOllamaReference(
      "hf.co/Qwen/Qwen3-8B-GGUF:Q4_K_M"
    )

    XCTAssertEqual(
      reference.modelIdentifier,
      "hf.co/Qwen/Qwen3-8B-GGUF:Q4_K_M"
    )
  }

  func testRejectsFileAndTreeURLs() {
    XCTAssertThrowsError(
      try HuggingFaceOllamaReference(
        "https://huggingface.co/owner/repo/tree/main"
      )
    )
    XCTAssertThrowsError(
      try HuggingFaceOllamaReference(
        "https://huggingface.co/owner/repo/blob/main/model.gguf"
      )
    )
  }

  func testRejectsNonHuggingFaceURL() {
    XCTAssertThrowsError(
      try HuggingFaceOllamaReference(
        "https://example.com/owner/repo"
      )
    )
  }
}
