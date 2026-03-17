import SwiftUI

/// Full-screen story viewer similar to Instagram/Facebook stories.
///
/// Displays slides with progress bars, auto-advance, tap/swipe navigation,
/// and close button. Renders slide content using `DesignRenderer`.
public struct StoryViewerView: View {
    let story: StoryResponse
    let client: RelevaClient
    let onLinkTap: ((String) -> Void)
    let onClose: () -> Void

    @State private var currentSlideIndex = 0
    @State private var progress: CGFloat = 0
    @State private var storyCompleteTracked = false
    @State private var timer: Timer?

    private var currentSlide: StorySlideResponse {
        story.slides[currentSlideIndex]
    }

    private var activeColor: Color {
        DesignRenderer.parseColor(story.progressIndicatorColor) ?? .white
    }

    private var inactiveColor: Color {
        DesignRenderer.parseColor(story.progressIndicatorInactiveColor) ?? Color.white.opacity(0.3)
    }

    private var slideBackgroundColor: Color {
        guard let design = currentSlide.design,
              let body = design["body"] as? [String: Any],
              let values = body["values"] as? [String: Any] else { return .black }
        return DesignRenderer.parseColor(values["backgroundColor"]) ?? .black
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                slideBackgroundColor.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Progress bars + close button
                    HStack(spacing: 4) {
                        ForEach(0..<story.slides.count, id: \.self) { index in
                            ProgressBarSegment(
                                isActive: index == currentSlideIndex,
                                isCompleted: index < currentSlideIndex,
                                progress: index == currentSlideIndex ? progress : 0,
                                activeColor: activeColor,
                                inactiveColor: inactiveColor
                            )
                        }

                        Button {
                            close()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(activeColor)
                                .frame(width: 28, height: 28)
                        }
                        .padding(.leading, 4)
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 8)

                    // Slide content
                    ZStack {
                        if let design = currentSlide.design {
                            ScrollView {
                                DesignRenderer.render(
                                    design: design,
                                    maxWidth: geometry.size.width,
                                    onLinkTap: { url in
                                        trackSlideClick()
                                        onLinkTap(url)
                                    }
                                )
                            }
                        }

                        // Navigation tap areas
                        HStack(spacing: 0) {
                            // Left half - previous
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { goToPreviousSlide() }

                            // Right half - next
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture { goToNextSlide() }
                        }
                        .gesture(
                            DragGesture(minimumDistance: 50)
                                .onEnded { value in
                                    if value.translation.width > 50 {
                                        goToPreviousSlide()
                                    } else if value.translation.width < -50 {
                                        goToNextSlide()
                                    }
                                }
                        )
                    }
                    .frame(maxHeight: .infinity)

                    // Action button
                    if let actionType = currentSlide.actionType,
                       actionType != "none",
                       let actionLabel = currentSlide.actionLabel,
                       !actionLabel.isEmpty {
                        Button {
                            handleSlideAction()
                        } label: {
                            Text(actionLabel)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.white)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                    }
                }
            }
        }
        .onAppear {
            trackSlideView()
            startSlideTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    // MARK: - Timer

    private func startSlideTimer() {
        timer?.invalidate()
        progress = 0

        let duration = TimeInterval(currentSlide.durationSeconds)
        let interval: TimeInterval = 0.05
        let increment = CGFloat(interval / duration)

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            DispatchQueue.main.async {
                progress += increment
                if progress >= 1.0 {
                    goToNextSlide()
                }
            }
        }
    }

    // MARK: - Navigation

    private func goToNextSlide() {
        timer?.invalidate()

        if currentSlideIndex < story.slides.count - 1 {
            currentSlideIndex += 1
            trackSlideView()
            startSlideTimer()
        } else {
            // Reached the end
            if !storyCompleteTracked {
                storyCompleteTracked = true
                trackEvent("storyComplete")
            }

            switch story.endBehavior {
            case "loop":
                currentSlideIndex = 0
                trackSlideView()
                startSlideTimer()
            case "stayOnLast":
                progress = 1.0
            default: // "dismiss"
                close()
            }
        }
    }

    private func goToPreviousSlide() {
        timer?.invalidate()

        if currentSlideIndex > 0 {
            currentSlideIndex -= 1
            trackSlideView()
        }
        startSlideTimer()
    }

    private func close() {
        timer?.invalidate()
        trackEvent("storyClose")
        onClose()
    }

    private func handleSlideAction() {
        trackSlideClick()
        if let url = currentSlide.actionUrl, !url.isEmpty {
            if currentSlide.actionType == "dismiss" {
                onLinkTap(url)
                close()
            } else {
                onLinkTap(url)
            }
        }
    }

    // MARK: - Tracking

    private func trackEvent(_ action: String) {
        client.storyAction(story, action: action)
    }

    private func trackSlideView() {
        client.storyAction(story, action: "storySlideView", slideId: currentSlide.id)
    }

    private func trackSlideClick() {
        client.storyAction(story, action: "storySlideClick", slideId: currentSlide.id)
    }
}

// MARK: - Progress Bar Segment

private struct ProgressBarSegment: View {
    let isActive: Bool
    let isCompleted: Bool
    let progress: CGFloat
    let activeColor: Color
    let inactiveColor: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background
                Capsule()
                    .fill(inactiveColor)

                // Fill
                if isCompleted {
                    Capsule()
                        .fill(activeColor)
                } else if isActive {
                    Capsule()
                        .fill(activeColor)
                        .frame(width: geometry.size.width * progress)
                }
            }
        }
        .frame(height: 3)
    }
}
