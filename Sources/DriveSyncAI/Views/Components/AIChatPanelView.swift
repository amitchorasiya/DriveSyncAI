// Copyright 2026 Amit Chorasiya. All rights reserved.
// Licensed under the Business Source License 1.1. See LICENSE file.

import SwiftUI

// MARK: - Side Drawer Chat Panel

struct AIChatPanelView<PendingContent: View, ExtraContent: View>: View {
    let title: String
    let placeholder: String
    let messages: [OrganizationChatMessage]
    @Binding var input: String
    let isLoading: Bool
    let quickActions: [String]
    let onSend: () -> Void
    let onClose: () -> Void
    @ViewBuilder var pendingContent: () -> PendingContent
    @ViewBuilder var extraContent: () -> ExtraContent

    @FocusState private var isFieldFocused: Bool
    @State private var isExpanded = false

    private let accentGradient = LinearGradient(
        colors: [Color(red: 0.38, green: 0.22, blue: 0.82), Color(red: 0.25, green: 0.35, blue: 0.88)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    private var panelWidth: CGFloat { isExpanded ? 520 : 380 }

    var body: some View {
        VStack(spacing: 0) {
            drawerHeader
            Divider().opacity(0.4)
            messageArea
            inputBar
        }
        .padding(.bottom, 8)
        .frame(width: panelWidth)
        .frame(maxHeight: .infinity)
        .background(Color.dsBackground)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(Color.dsSeparator.opacity(0.3))
                .frame(width: 1)
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    // MARK: - Drawer Header

    private var drawerHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accentGradient)
                    .frame(width: 26, height: 26)
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.dsPrimaryText)
                HStack(spacing: 4) {
                    Circle().fill(.green).frame(width: 5, height: 5)
                    Text("Online")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.dsTertiaryText)
                }
            }

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() }
            } label: {
                Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsSecondaryText)
                    .frame(width: 26, height: 26)
                    .background(Color.dsSecondaryFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse panel" : "Expand panel")

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { onClose() }
            } label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color.dsSecondaryText)
                    .frame(width: 26, height: 26)
                    .background(Color.dsSecondaryFill.opacity(0.5), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .buttonStyle(.plain)
            .help("Close panel")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: - Message Area

    private var messageArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(messages) { message in
                        chatBubble(message).id(message.id)
                    }

                    if isLoading {
                        typingIndicator
                    }

                    if !quickActions.isEmpty && messages.count <= 1 && !isLoading {
                        quickActionChips.padding(.top, 8)
                    }

                    pendingContent()
                    extraContent()
                }
                .padding(.vertical, 12)
            }
            .onChange(of: messages.count) {
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
            .onChange(of: isLoading) {
                if isLoading {
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("typing", anchor: .bottom) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.dsSecondaryBackground.opacity(0.35))
    }

    // MARK: - Typing Indicator

    private var typingIndicator: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                buddyAvatar(size: 22)
                HStack(spacing: 4) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color.dsSecondaryText.opacity(0.4))
                            .frame(width: 5, height: 5)
                            .offset(y: isLoading ? -3 : 0)
                            .animation(
                                .easeInOut(duration: 0.45).repeatForever(autoreverses: true).delay(Double(i) * 0.15),
                                value: isLoading
                            )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.dsSecondaryFill.opacity(0.5), in: BubbleShape(isUser: false))
            }
            .padding(.horizontal, 14)
            Spacer(minLength: 60)
        }
        .padding(.top, 4)
        .id("typing")
    }

    // MARK: - Quick Actions

    private var quickActionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Suggestions")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Color.dsTertiaryText)
                .textCase(.uppercase)
                .tracking(0.5)
                .padding(.horizontal, 14)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(quickActions, id: \.self) { action in
                    Button {
                        input = action
                        onSend()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(accentGradient)
                            Text(action)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Color.dsPrimaryText.opacity(0.85))
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.dsSecondaryFill.opacity(0.4))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.dsSeparator.opacity(0.3), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 4)
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.3)
            HStack(spacing: 8) {
                ZStack(alignment: .leading) {
                    if input.isEmpty {
                        Text(placeholder)
                            .font(.system(size: 13))
                            .foregroundStyle(Color.dsTertiaryText)
                            .padding(.leading, 12)
                    }
                    TextField("", text: $input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.dsPrimaryText)
                        .padding(.leading, 12)
                        .padding(.trailing, 4)
                        .focused($isFieldFocused)
                        .onSubmit {
                            guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                            onSend()
                        }
                }
                .frame(height: 36)
                .background(Color.dsSecondaryFill.opacity(0.4), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(isFieldFocused ? Color.dsAction.opacity(0.5) : Color.dsSeparator.opacity(0.2), lineWidth: isFieldFocused ? 1.5 : 0.5)
                )

                sendButton
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .background(Color.dsBackground)
    }

    @ViewBuilder
    private var sendButton: some View {
        if isLoading {
            ProgressView().controlSize(.small).frame(width: 32, height: 32)
        } else {
            let canSend = !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Button { onSend() } label: {
                ZStack {
                    Circle()
                        .fill(canSend ? AnyShapeStyle(accentGradient) : AnyShapeStyle(Color.dsSecondaryFill.opacity(0.5)))
                        .frame(width: 32, height: 32)
                    Image(systemName: "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(canSend ? .white : Color.dsTertiaryText)
                }
            }
            .buttonStyle(.plain)
            .disabled(!canSend)
        }
    }

    // MARK: - Chat Bubble

    private func chatBubble(_ message: OrganizationChatMessage) -> some View {
        let isUser = message.role == "user"
        let isSystem = message.role == "system"

        return VStack(spacing: 0) {
            if isSystem {
                systemBubble(message)
            } else if isUser {
                userBubble(message)
            } else {
                assistantBubble(message)
            }
        }
        .padding(.top, 6)
    }

    private func assistantBubble(_ message: OrganizationChatMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            buddyAvatar(size: 22)
            Text(message.text)
                .font(.system(size: 12.5))
                .foregroundStyle(Color.dsPrimaryText)
                .lineSpacing(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Color.dsSecondaryFill.opacity(0.5), in: BubbleShape(isUser: false))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
    }

    private func userBubble(_ message: OrganizationChatMessage) -> some View {
        HStack {
            Spacer(minLength: 44)
            Text(message.text)
                .font(.system(size: 12.5))
                .foregroundStyle(.white)
                .lineSpacing(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(accentGradient, in: BubbleShape(isUser: true))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
    }

    private func systemBubble(_ message: OrganizationChatMessage) -> some View {
        HStack(spacing: 6) {
            Image(systemName: message.text.contains("Re-analyzing") ? "arrow.triangle.2.circlepath" : "checkmark.circle.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.green)
            Text(message.text)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.dsSecondaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 14)
    }

    private func buddyAvatar(size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
                .fill(accentGradient)
                .frame(width: size, height: size)
            Image(systemName: "sparkles")
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Bubble Shape

struct BubbleShape: Shape {
    let isUser: Bool

    func path(in rect: CGRect) -> Path {
        let r: CGFloat = 14
        let t: CGFloat = 4
        var path = Path()
        if isUser {
            path.addRoundedRect(in: rect, cornerRadii: .init(topLeading: r, bottomLeading: r, bottomTrailing: t, topTrailing: r))
        } else {
            path.addRoundedRect(in: rect, cornerRadii: .init(topLeading: t, bottomLeading: r, bottomTrailing: r, topTrailing: r))
        }
        return path
    }
}

// MARK: - Convenience Init

extension AIChatPanelView where PendingContent == EmptyView, ExtraContent == EmptyView {
    init(
        title: String,
        placeholder: String,
        messages: [OrganizationChatMessage],
        input: Binding<String>,
        isLoading: Bool,
        quickActions: [String] = [],
        onSend: @escaping () -> Void,
        onClose: @escaping () -> Void
    ) {
        self.title = title
        self.placeholder = placeholder
        self.messages = messages
        self._input = input
        self.isLoading = isLoading
        self.quickActions = quickActions
        self.onSend = onSend
        self.onClose = onClose
        self.pendingContent = { EmptyView() }
        self.extraContent = { EmptyView() }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > maxW && x > 0 { y += rowH + spacing; x = 0; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
        return CGSize(width: maxW, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for sub in subviews {
            let s = sub.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX && x > bounds.minX { y += rowH + spacing; x = bounds.minX; rowH = 0 }
            sub.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}

// MARK: - Toolbar Toggle Button

struct AIChatToggleButton: View {
    @Binding var isVisible: Bool

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                isVisible.toggle()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(red: 0.38, green: 0.22, blue: 0.82), Color(red: 0.25, green: 0.35, blue: 0.88)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                Text("AI")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.dsSecondaryText)
                Image(systemName: "sidebar.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isVisible ? Color.dsAction : Color.dsSecondaryText)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                isVisible
                    ? AnyShapeStyle(Color.dsAction.opacity(0.1))
                    : AnyShapeStyle(Color.dsSecondaryFill.opacity(0.5)),
                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isVisible ? Color.dsAction.opacity(0.3) : Color.dsSeparator.opacity(0.3), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .help(isVisible ? "Hide DriveSyncAI Buddy" : "Show DriveSyncAI Buddy")
    }
}
