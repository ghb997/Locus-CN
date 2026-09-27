import SwiftUI

struct JoystickPad: View {
    var onChange: (CGVector) -> Void

    @State private var dragOffset: CGSize = .zero
    @Environment(\.scenePhase) private var scenePhase
    @State private var pulse: Task<Void, Never>?
    private let radius: CGFloat = 52

    var body: some View {
        HStack {
            VStack {
                direction("arrow.up", label: L10n.tr("Move north"), vector: CGVector(dx: 0, dy: -1))
                HStack {
                    direction("arrow.left", label: L10n.tr("Move west"), vector: CGVector(dx: -1, dy: 0))
                    direction("stop.fill", label: L10n.tr("Release joystick"), vector: .zero)
                    direction("arrow.right", label: L10n.tr("Move east"), vector: CGVector(dx: 1, dy: 0))
                }
                direction("arrow.down", label: L10n.tr("Move south"), vector: CGVector(dx: 0, dy: 1))
            }
            Spacer()
            ZStack {
            Circle()
                .frame(width: radius * 2 + 28, height: radius * 2 + 28)
                .locusGlass(.clear, in: Circle())

            Circle()
                .stroke(LocusTheme.accent.opacity(0.4), lineWidth: 2)
                .frame(width: radius * 2, height: radius * 2)

            Circle()
                .fill(LocusTheme.accent)
                .frame(width: 44, height: 44)
                .shadow(color: LocusTheme.accent.opacity(0.45), radius: 8)
                .offset(dragOffset)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let limited = clamp(value.translation, radius: radius)
                            dragOffset = limited
                            onChange(CGVector(dx: limited.width / radius, dy: limited.height / radius))
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                dragOffset = .zero
                            }
                            onChange(.zero)
                        }
                )
        }
            .accessibilityLabel(L10n.tr("Movement joystick"))
            .accessibilityAction(named: L10n.tr("Move north")) { nudge(CGVector(dx: 0, dy: -1)) }
            .accessibilityAction(named: L10n.tr("Move south")) { nudge(CGVector(dx: 0, dy: 1)) }
            .accessibilityAction(named: L10n.tr("Move east")) { nudge(CGVector(dx: 1, dy: 0)) }
            .accessibilityAction(named: L10n.tr("Move west")) { nudge(CGVector(dx: -1, dy: 0)) }
        }
        .onDisappear { reset() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { reset() } }
    }

    private func direction(_ icon: String, label: String, vector: CGVector) -> some View {
        Button { nudge(vector) } label: { Image(systemName: icon).frame(width: 44, height: 44).background(.thinMaterial, in: Circle()) }
            .accessibilityLabel(label)
    }
    private func nudge(_ vector: CGVector) {
        pulse?.cancel(); onChange(vector)
        pulse = Task { do { try await Task.sleep(for: .seconds(1)) } catch { return }; onChange(.zero) }
    }
    private func reset() { pulse?.cancel(); dragOffset = .zero; onChange(.zero) }

    private func clamp(_ translation: CGSize, radius: CGFloat) -> CGSize {
        let length = sqrt(translation.width * translation.width + translation.height * translation.height)
        guard length > radius else { return translation }
        let scale = radius / length
        return CGSize(width: translation.width * scale, height: translation.height * scale)
    }
}
