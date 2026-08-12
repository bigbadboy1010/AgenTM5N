import Foundation

public enum CoreMLAgentTools {
  public static let definitions: [ProviderToolDefinition] = [
    ProviderToolDefinition(
      name: "coreml_list_models",
      description: "List locally registered Core ML models without exposing internal filesystem paths. Returns model IDs, names, active state, inputs, outputs and compute policy.",
      parameters: objectSchema(properties: [:])
    ),
    ProviderToolDefinition(
      name: "coreml_describe_model",
      description: "Describe one registered Core ML model by model name or UUID. If model is omitted, describe the active model.",
      parameters: objectSchema(
        properties: [
          "model": stringSchema("Optional registered model name or UUID. Defaults to the active model.")
        ]
      )
    ),
    ProviderToolDefinition(
      name: "coreml_predict",
      description: "Run a local Core ML prediction through AgenTM5N Neural Runtime. Manual mode preserves the selected Core ML compute policy; Adaptive mode uses the hardware/OS-specific routing profile and safely falls back to Core ML Automatic when specialized execution fails. Use coreml_describe_model first. Scalar Double, Int64 and String features are supported; MultiArray inputs use nested numeric JSON arrays; image inputs use a local image-file path string matching the model's image constraint.",
      parameters: objectSchema(
        required: ["input"],
        properties: [
          "model": stringSchema("Optional registered model name or UUID. Defaults to the active model."),
          "input": .object([
            "type": .string("object"),
            "description": .string("Prediction input object. Use numbers/strings for scalar features, nested numeric arrays for MLMultiArray features, and a local image-file path string for image features."),
            "additionalProperties": .bool(true),
          ]),
        ]
      )
    ),
  ]

  public static func handles(_ call: ProviderToolCall) -> Bool {
    definitions.contains { $0.function.name == call.function.name }
  }

  public static func risk(for call: ProviderToolCall) -> ToolRisk {
    call.function.name == "coreml_predict" ? .execute : .read
  }

  public static func summary(for call: ProviderToolCall) -> String {
    let arguments = call.function.arguments.keys.sorted().compactMap { key -> String? in
      guard let value = call.function.arguments[key] else { return nil }
      if key == "input" {
        return "input: <\(value.compactDescription.utf8.count) Bytes>"
      }
      return "\(key): \(value.compactDescription)"
    }
    return arguments.isEmpty
      ? call.function.name
      : "\(call.function.name) — \(arguments.joined(separator: ", "))"
  }

  private static func objectSchema(
    required: [String] = [],
    properties: [String: JSONValue]
  ) -> JSONValue {
    var schema: [String: JSONValue] = [
      "type": .string("object"),
      "properties": .object(properties),
      "additionalProperties": .bool(false),
    ]
    if !required.isEmpty {
      schema["required"] = .array(required.map(JSONValue.string))
    }
    return .object(schema)
  }

  private static func stringSchema(_ description: String) -> JSONValue {
    .object([
      "type": .string("string"),
      "description": .string(description),
    ])
  }
}
