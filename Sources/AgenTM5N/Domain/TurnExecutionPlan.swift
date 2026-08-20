import Foundation

public enum TurnExecutionOrigin: String, Codable, Equatable, Sendable {
  case manualProvider
  case hybridAppleOnDevice
  case automaticModelProfile
}

/// Immutable execution state for one local chat turn.
///
/// `AppConfiguration` remains the persisted user preference. A turn captures a
/// value snapshot and provider routing derives a new value for that turn only;
/// no execution path needs to mutate and later restore global app settings.
public struct TurnExecutionPlan: Equatable, Sendable {
  public let turnID: UUID
  public let origin: TurnExecutionOrigin
  public let configuration: AppConfiguration
  public let operatingConfiguration: AgentOperatingLayerConfiguration
  public let automaticBudget: AutomaticInferenceBudget?

  public init(
    turnID: UUID,
    origin: TurnExecutionOrigin,
    configuration: AppConfiguration,
    operatingConfiguration: AgentOperatingLayerConfiguration,
    automaticBudget: AutomaticInferenceBudget? = nil
  ) {
    self.turnID = turnID
    self.origin = origin
    self.configuration = configuration
    self.operatingConfiguration = operatingConfiguration
    self.automaticBudget = automaticBudget
  }

  public var heavyRuntime: HeavyInferenceRuntime? {
    HeavyInferenceRuntime(
      providerKind: configuration.providerKind,
      localInferenceRuntime: operatingConfiguration.localInferenceRuntime
    )
  }

  public static func manual(
    turnID: UUID = UUID(),
    configuration: AppConfiguration,
    operatingConfiguration: AgentOperatingLayerConfiguration
  ) -> TurnExecutionPlan {
    TurnExecutionPlan(
      turnID: turnID,
      origin: .manualProvider,
      configuration: configuration,
      operatingConfiguration: operatingConfiguration
    )
  }

  public static func hybridAppleOnDevice(
    turnID: UUID = UUID(),
    configuration: AppConfiguration,
    operatingConfiguration: AgentOperatingLayerConfiguration
  ) -> TurnExecutionPlan {
    var routeConfiguration = configuration
    routeConfiguration.providerKind = .appleOnDevice
    routeConfiguration.baseURL = ProviderKind.appleOnDevice.defaultBaseURL
    routeConfiguration.model = "Apple System Language Model"
    routeConfiguration.apiKeySecretID = nil

    return TurnExecutionPlan(
      turnID: turnID,
      origin: .hybridAppleOnDevice,
      configuration: routeConfiguration,
      operatingConfiguration: operatingConfiguration,
      automaticBudget: AutomaticInferenceBudget.automatic(
        runtime: .appleFoundationModels,
        contextWindow: operatingConfiguration.numContext
      )
    )
  }
}
