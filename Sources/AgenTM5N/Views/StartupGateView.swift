import AppKit
import SwiftUI

/// Native startup experience for AgenTM5N.
///
/// The splash is not a fixed-delay movie. It is shown while AppState performs
/// its real bootstrap work and transitions away as soon as bootstrap returns.
/// Accessibility Reduce Motion is respected automatically.
struct StartupGateView: View {
  @EnvironmentObject private var appState: AppState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  @State private var bootstrapStarted = false
  @State private var isReady = false

  var body: some View {
    ZStack {
      RootView()
        .environmentObject(appState)
        .opacity(isReady ? 1 : 0)
        .scaleEffect(isReady || reduceMotion ? 1 : 0.992)
        .allowsHitTesting(isReady)
        .accessibilityHidden(!isReady)

      if !isReady {
        NeuralStartupView(reduceMotion: reduceMotion)
          .transition(.opacity)
          .zIndex(10)
      }
    }
    .background(Color(nsColor: .windowBackgroundColor))
    .task {
      guard !bootstrapStarted else { return }
      bootstrapStarted = true

      await appState.bootstrap()
      await Task.yield()

      if reduceMotion {
        isReady = true
      } else {
        withAnimation(.easeOut(duration: 0.42)) {
          isReady = true
        }
      }
    }
  }
}

private struct NeuralStartupView: View {
  let reduceMotion: Bool

  @Environment(\.colorScheme) private var colorScheme
  @State private var appeared = false

  private var versionText: String {
    let version = Bundle.main.object(
      forInfoDictionaryKey: "CFBundleShortVersionString"
    ) as? String ?? ""
    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""

    if version.isEmpty && build.isEmpty { return "AgenTM5N" }
    if build.isEmpty { return "Version \(version)" }
    return "Version \(version) · Build \(build)"
  }

  var body: some View {
    ZStack {
      background

      NeuralNetworkCanvas(reduceMotion: reduceMotion)
        .opacity(colorScheme == .dark ? 0.88 : 0.62)
        .ignoresSafeArea()

      VStack(spacing: 24) {
        Spacer(minLength: 28)

        appIdentity

        runtimeChips

        HStack(spacing: 10) {
          ProgressView()
            .controlSize(.small)
          Text(
            L10n.text(
              de: "Agent Runtime wird initialisiert…",
              en: "Initializing agent runtime…",
              fr: "Initialisation du runtime agent…"
            )
          )
          .font(.subheadline.weight(.medium))
          .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)

        Spacer()

        Text(versionText)
          .font(.caption.monospacedDigit())
          .foregroundStyle(.tertiary)
          .padding(.bottom, 24)
      }
      .padding(.horizontal, 36)
    }
    .onAppear {
      guard !reduceMotion else {
        appeared = true
        return
      }
      withAnimation(.easeOut(duration: 0.55)) {
        appeared = true
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("AgenTM5N")
    .accessibilityHint(
      L10n.text(
        de: "Die Anwendung wird gestartet.",
        en: "The application is starting.",
        fr: "L’application démarre."
      )
    )
  }

  private var background: some View {
    ZStack {
      Color(nsColor: .windowBackgroundColor)

      RadialGradient(
        colors: [
          Color.accentColor.opacity(colorScheme == .dark ? 0.20 : 0.12),
          Color.clear,
        ],
        center: .center,
        startRadius: 20,
        endRadius: 430
      )

      LinearGradient(
        colors: [
          Color.primary.opacity(colorScheme == .dark ? 0.025 : 0.018),
          Color.clear,
          Color.accentColor.opacity(colorScheme == .dark ? 0.045 : 0.03),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
    .ignoresSafeArea()
  }

  private var appIdentity: some View {
    VStack(spacing: 16) {
      ZStack {
        Circle()
          .fill(Color.accentColor.opacity(0.12))
          .frame(width: 126, height: 126)
          .blur(radius: reduceMotion ? 0 : 8)
          .scaleEffect(appeared ? 1 : 0.78)

        Circle()
          .stroke(Color.accentColor.opacity(0.28), lineWidth: 1)
          .frame(width: 112, height: 112)
          .scaleEffect(appeared ? 1 : 0.86)

        Image(nsImage: NSApplication.shared.applicationIconImage)
          .resizable()
          .interpolation(.high)
          .scaledToFit()
          .frame(width: 86, height: 86)
          .shadow(color: Color.accentColor.opacity(0.28), radius: 18, y: 5)
          .scaleEffect(appeared ? 1 : 0.9)
      }

      VStack(spacing: 5) {
        Text("AgenTM5N")
          .font(.system(size: 36, weight: .bold, design: .rounded))
          .tracking(1.2)

        Text("NATIVE AGENT RUNTIME")
          .font(.caption.weight(.semibold))
          .tracking(2.3)
          .foregroundStyle(.secondary)
      }
      .opacity(appeared ? 1 : 0)
      .offset(y: appeared ? 0 : 8)
    }
  }

  private var runtimeChips: some View {
    HStack(spacing: 9) {
      StartupChip(title: "Agent Runtime", symbol: "sparkles")
      StartupChip(title: "Tool Registry", symbol: "wrench.and.screwdriver")
      StartupChip(title: "Neural Engine", symbol: "brain")
    }
    .opacity(appeared ? 1 : 0)
    .offset(y: appeared ? 0 : 10)
  }
}

private struct StartupChip: View {
  let title: String
  let symbol: String

  var body: some View {
    Label(title, systemImage: symbol)
      .font(.caption.weight(.medium))
      .foregroundStyle(.secondary)
      .padding(.horizontal, 11)
      .padding(.vertical, 7)
      .background(.thinMaterial, in: Capsule())
      .overlay {
        Capsule()
          .stroke(Color.primary.opacity(0.08), lineWidth: 1)
      }
  }
}

private struct NeuralNetworkCanvas: View {
  let reduceMotion: Bool

  private struct Node {
    let x: Double
    let y: Double
    let phase: Double
    let radius: Double
  }

  private let nodes: [Node] = [
    .init(x: 0.08, y: 0.20, phase: 0.2, radius: 3.0),
    .init(x: 0.20, y: 0.38, phase: 1.1, radius: 4.0),
    .init(x: 0.13, y: 0.72, phase: 2.4, radius: 2.8),
    .init(x: 0.31, y: 0.16, phase: 3.3, radius: 3.4),
    .init(x: 0.36, y: 0.63, phase: 4.2, radius: 4.2),
    .init(x: 0.49, y: 0.29, phase: 5.1, radius: 3.2),
    .init(x: 0.55, y: 0.76, phase: 0.8, radius: 3.8),
    .init(x: 0.68, y: 0.18, phase: 1.9, radius: 2.9),
    .init(x: 0.72, y: 0.52, phase: 2.9, radius: 4.1),
    .init(x: 0.84, y: 0.32, phase: 4.0, radius: 3.3),
    .init(x: 0.90, y: 0.68, phase: 5.4, radius: 3.7),
    .init(x: 0.64, y: 0.86, phase: 3.7, radius: 2.8),
    .init(x: 0.28, y: 0.86, phase: 2.1, radius: 3.1),
  ]

  private let edges: [(Int, Int)] = [
    (0, 1), (0, 3), (1, 3), (1, 4), (1, 5), (2, 4), (2, 12),
    (3, 5), (4, 5), (4, 6), (4, 12), (5, 7), (5, 8), (6, 8),
    (6, 11), (7, 8), (7, 9), (8, 9), (8, 10), (8, 11), (9, 10),
    (10, 11), (6, 12),
  ]

  var body: some View {
    TimelineView(.animation(minimumInterval: reduceMotion ? 1.0 : 1.0 / 30.0)) { timeline in
      Canvas { context, size in
        let time = timeline.date.timeIntervalSinceReferenceDate
        let points = nodes.map { node in
          point(for: node, time: time, size: size)
        }

        for edge in edges {
          guard edge.0 < points.count, edge.1 < points.count else { continue }
          var path = Path()
          path.move(to: points[edge.0])
          path.addLine(to: points[edge.1])
          context.stroke(
            path,
            with: .color(Color.accentColor.opacity(0.16)),
            lineWidth: 0.8
          )
        }

        for (index, point) in points.enumerated() {
          let node = nodes[index]
          let pulse = reduceMotion
            ? 1.0
            : 0.82 + 0.18 * sin(time * 1.8 + node.phase)
          let radius = node.radius * pulse
          let rect = CGRect(
            x: point.x - radius,
            y: point.y - radius,
            width: radius * 2,
            height: radius * 2
          )
          context.fill(
            Path(ellipseIn: rect),
            with: .color(Color.accentColor.opacity(0.55))
          )

          let haloRadius = radius * 2.6
          let halo = CGRect(
            x: point.x - haloRadius,
            y: point.y - haloRadius,
            width: haloRadius * 2,
            height: haloRadius * 2
          )
          context.fill(
            Path(ellipseIn: halo),
            with: .color(Color.accentColor.opacity(0.045))
          )
        }
      }
    }
  }

  private func point(
    for node: Node,
    time: TimeInterval,
    size: CGSize
  ) -> CGPoint {
    guard !reduceMotion else {
      return CGPoint(x: size.width * node.x, y: size.height * node.y)
    }

    let driftX = sin(time * 0.42 + node.phase) * 8.0
    let driftY = cos(time * 0.36 + node.phase * 1.3) * 7.0
    return CGPoint(
      x: size.width * node.x + driftX,
      y: size.height * node.y + driftY
    )
  }
}
