import SwiftUI
import Combine

/// A SwiftUI view modifier that listens for NPS display events and shows the survey.
///
/// Usage:
/// ```swift
/// ContentView()
///     .npsDisplay(onSubmit: { token, score, comment in
///         client.submitNpsResponse(token: token, score: score, comment: comment)
///     })
/// ```
public struct NpsDisplayModifier: ViewModifier {
    let onSubmit: (String, Int, String?) -> Void
    let onSkip: (() -> Void)?

    @StateObject private var viewModel = NpsDisplayViewModel()

    public func body(content: Content) -> some View {
        content
            .sheet(item: $viewModel.activeConfig) { config in
                NpsSurveyView(
                    config: config,
                    onSubmit: onSubmit,
                    onSkip: onSkip
                )
                .modifier(PresentationDetentsModifier())
            }
    }
}

// MARK: - View Extension

extension View {
    /// Add NPS survey display capability to this view.
    /// - Parameters:
    ///   - onSubmit: Called when the user submits a score (and optional comment)
    ///   - onSkip: Called when the user taps Skip
    public func npsDisplay(
        onSubmit: @escaping (String, Int, String?) -> Void,
        onSkip: (() -> Void)? = nil
    ) -> some View {
        self.modifier(NpsDisplayModifier(
            onSubmit: onSubmit,
            onSkip: onSkip
        ))
    }
}

// MARK: - ViewModel

class NpsDisplayViewModel: ObservableObject {
    @Published var activeConfig: IdentifiableNpsConfig?
    private var cancellable: AnyCancellable?

    init() {
        cancellable = NpsDisplayController.shared.npsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] config in
                self?.activeConfig = IdentifiableNpsConfig(config: config)
            }
    }
}

/// Wrapper to make NpsConfig identifiable for .sheet(item:)
struct IdentifiableNpsConfig: Identifiable {
    let id = UUID()
    let config: NpsConfig
}

// MARK: - NPS Survey View

struct NpsSurveyView: View {
    let config: IdentifiableNpsConfig
    let onSubmit: (String, Int, String?) -> Void
    let onSkip: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var step: NpsStep = .score
    @State private var selectedScore: Int?
    @State private var comment: String = ""
    @State private var dismissTimer: Timer?

    private var nps: NpsConfig { config.config }

    private var primaryColor: Color {
        let isDark = colorScheme == .dark
        if isDark, let darkColor = nps.appearance.dark?.primaryColor {
            return DesignRenderer.parseColor(darkColor) ?? DesignRenderer.parseColor(nps.appearance.primaryColor) ?? Color(red: 108/255, green: 63/255, blue: 196/255)
        }
        return DesignRenderer.parseColor(nps.appearance.primaryColor) ?? Color(red: 108/255, green: 63/255, blue: 196/255)
    }

    private var bgColor: Color {
        let isDark = colorScheme == .dark
        if isDark, let darkColor = nps.appearance.dark?.backgroundColor {
            return DesignRenderer.parseColor(darkColor) ?? .white
        }
        return DesignRenderer.parseColor(nps.appearance.backgroundColor) ?? .white
    }

    private var textColor: Color {
        let isDark = colorScheme == .dark
        if isDark, let darkColor = nps.appearance.dark?.textColor {
            return DesignRenderer.parseColor(darkColor) ?? Color(white: 0.1)
        }
        return DesignRenderer.parseColor(nps.appearance.textColor) ?? Color(white: 0.1)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 40, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 8)

            switch step {
            case .score:
                scoreStep
            case .followUp:
                followUpStep
            case .thankYou:
                thankYouStep
            }
        }
        .background(bgColor)
        .onDisappear {
            dismissTimer?.invalidate()
        }
    }

    // MARK: - Score Step

    private var scoreStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Logo
            if let logoUrl = nps.appearance.logoUrl, let url = URL(string: logoUrl) {
                HStack {
                    Spacer()
                    AsyncImage(url: url) { image in
                        image.resizable().aspectRatio(contentMode: .fit)
                    } placeholder: {
                        EmptyView()
                    }
                    .frame(height: 40)
                    Spacer()
                }
            }

            // Question
            Text(nps.question)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(textColor)

            // Score buttons 0-10
            HStack(spacing: 4) {
                ForEach(0...10, id: \.self) { score in
                    Button {
                        onScoreSelected(score)
                    } label: {
                        let radius = buttonCornerRadius(for: nps.appearance.buttonStyle)
                        Text("\(score)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(selectedScore == score ? .white : primaryColor)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background(
                                RoundedRectangle(cornerRadius: radius)
                                    .fill(selectedScore == score ? primaryColor : primaryColor.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: radius)
                                    .stroke(selectedScore == score ? primaryColor : primaryColor.opacity(0.3), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // Scale labels
            HStack {
                if let low = nps.scaleLowLabel {
                    Text(low)
                        .font(.system(size: 12))
                        .foregroundColor(textColor.opacity(0.6))
                }
                Spacer()
                if let high = nps.scaleHighLabel {
                    Text(high)
                        .font(.system(size: 12))
                        .foregroundColor(textColor.opacity(0.6))
                }
            }

            // Skip button
            if let skipLabel = nps.skipLabel {
                HStack {
                    Spacer()
                    Button {
                        onSkip?()
                        dismiss()
                    } label: {
                        Text(skipLabel)
                            .font(.system(size: 14))
                            .foregroundColor(textColor.opacity(0.5))
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Follow-up Step

    private var followUpStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let question = selectedScore.flatMap({ nps.followUp?.forScore($0) }) {
                Text(question)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(textColor)
            }

            TextEditor(text: $comment)
                .frame(minHeight: 80, maxHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(textColor.opacity(0.2), lineWidth: 1)
                )
                .font(.system(size: 14))
                .foregroundColor(textColor)

            Button {
                submitFollowUp()
            } label: {
                Text(nps.submitLabel)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .background(
                RoundedRectangle(cornerRadius: buttonCornerRadius(for: nps.appearance.buttonStyle, height: 48))
                    .fill(submitButtonEnabled ? primaryColor : primaryColor.opacity(0.4))
            )
            .clipShape(RoundedRectangle(cornerRadius: buttonCornerRadius(for: nps.appearance.buttonStyle, height: 48)))
            .disabled(!submitButtonEnabled)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 24)
    }

    // MARK: - Thank You Step

    private var thankYouStep: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(primaryColor)

            Text(thankYouText)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(textColor)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
    }

    // MARK: - Logic

    private var submitButtonEnabled: Bool {
        if !nps.followUpRequired { return true }
        return !comment.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var thankYouText: String {
        guard let score = selectedScore else { return "Thank you!" }
        return nps.thankYou?.forScore(score) ?? "Thank you!"
    }

    private func onScoreSelected(_ score: Int) {
        selectedScore = score

        if let followUp = nps.followUp?.forScore(score), !followUp.isEmpty {
            step = .followUp
        } else {
            submitScore(score, comment: nil)
        }
    }

    private func submitScore(_ score: Int, comment: String?) {
        onSubmit(nps.token, score, comment)
        step = .thankYou
        // Auto-dismiss after 2 seconds
        dismissTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in
            DispatchQueue.main.async {
                dismiss()
            }
        }
    }

    private func submitFollowUp() {
        guard let score = selectedScore else { return }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        submitScore(score, comment: trimmed.isEmpty ? nil : trimmed)
    }

    // MARK: - Button Shape

    private func buttonCornerRadius(for style: String, height: CGFloat = 36) -> CGFloat {
        switch style {
        case "pill": return height / 2
        case "rounded": return 8
        default: return 0
        }
    }

}

// MARK: - Types

private enum NpsStep {
    case score, followUp, thankYou
}

// MARK: - Presentation Detents Compatibility

private struct PresentationDetentsModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content.presentationDetents([.medium, .large])
        } else {
            content
        }
    }
}
