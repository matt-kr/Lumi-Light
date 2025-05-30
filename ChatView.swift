import SwiftUI
import SwiftData

struct ChatView: View {
    @EnvironmentObject private var llmService: LlmInferenceService
    @EnvironmentObject private var userData: UserData
    @StateObject private var keyboard = KeyboardResponder()
    @Environment(\.modelContext) private var modelContext

    @State private var promptText: String = ""
    @State private var textEditorHeight: CGFloat = 38
    @FocusState private var isPromptFocused: Bool

    enum GlowState { case idle, pulsing, finalPulse, fadingOut }
    @State private var conversationGlowState: GlowState = .idle
    @State private var glowOpacity: Double = 0.0

    @State private var hasMadeFirstSubmission: Bool = false
    @State private var showComingSoonAlert: Bool = false

    let nasalizationFont = "Nasalization-Regular"
    let messageFontName = "Trebuchet MS"
    let singleLineMinHeight: CGFloat = 38
    private let collapsedMinHeight: CGFloat = 38

    @State private var keyboardAnimationDuration: TimeInterval = 0.25
    @State private var keyboardAnimationCurve: UIView.AnimationOptions = .curveEaseInOut
    
    private var stopButtonRed: Color { Color(red: 200/255, green: 70/255, blue: 70/255) }
    private var stopButtonRedShadow: Color { Color(red: 200/255, green: 70/255, blue: 70/255, opacity: 0.5) }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    init() {
        // Nav Bar Styling (as you had it)
        let fontNameForTitle = "Nasalization-Regular";let titleFontSize: CGFloat = 22;let barButtonFontSize: CGFloat = 17
        let titleUiFont = UIFont(name: fontNameForTitle, size: titleFontSize) ?? UIFont.systemFont(ofSize: titleFontSize, weight: .bold)
        let barButtonUiFont = UIFont(name: fontNameForTitle, size: barButtonFontSize) ?? UIFont.systemFont(ofSize: barButtonFontSize)
        let navBarBackgroundColor = UIColor(Color.sl_bgPrimary); let mainTitleAndBackButtonTextColor = UIColor(Color.sl_textPrimary); let glowUIColorForShadow = UIColor(Color.sl_glowColor)
        let appearance = UINavigationBarAppearance(); appearance.configureWithOpaqueBackground();
        appearance.backgroundColor = navBarBackgroundColor; appearance.shadowColor = .clear
        let titleShadow = NSShadow(); titleShadow.shadowColor = glowUIColorForShadow.withAlphaComponent(0.5); titleShadow.shadowOffset = CGSize(width: 0, height: 1); titleShadow.shadowBlurRadius = 2
        appearance.titleTextAttributes = [.font: titleUiFont, .foregroundColor: mainTitleAndBackButtonTextColor, .shadow: titleShadow]
        appearance.largeTitleTextAttributes = [.font: UIFont(name: fontNameForTitle, size: 34) ?? UIFont.systemFont(ofSize: 34, weight: .bold), .foregroundColor: mainTitleAndBackButtonTextColor, .shadow: titleShadow]
        let barButtonAppearance = UIBarButtonItemAppearance(); barButtonAppearance.normal.titleTextAttributes = [.font: barButtonUiFont, .foregroundColor: mainTitleAndBackButtonTextColor]
        barButtonAppearance.highlighted.titleTextAttributes = [.font: barButtonUiFont, .foregroundColor: mainTitleAndBackButtonTextColor.withAlphaComponent(0.7)]
        barButtonAppearance.disabled.titleTextAttributes = [.font: barButtonUiFont, .foregroundColor: mainTitleAndBackButtonTextColor.withAlphaComponent(0.5)]
        appearance.buttonAppearance = barButtonAppearance; appearance.backButtonAppearance = barButtonAppearance; appearance.doneButtonAppearance = barButtonAppearance
        UINavigationBar.appearance().standardAppearance = appearance; UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance; UINavigationBar.appearance().compactScrollEdgeAppearance = appearance
        UINavigationBar.appearance().tintColor = mainTitleAndBackButtonTextColor
    }

    var body: some View {
        ZStack {
            Color.sl_bgPrimary.ignoresSafeArea()
            if llmService.isLoadingModel {
                loadingIndicatorView
            } else if let initError = llmService.initErrorMessage, !llmService.isModelReady {
                errorStateView(message: initError)
            } else if llmService.isModelReady {
                mainContentVStack
            } else {
                VStack { Spacer(); Text("Preparing Lumi...").font(.custom(nasalizationFont, size: 18)).foregroundColor(Color.sl_textSecondary); Spacer() }
            }
        }
        .toolbar { navigationBarToolbarContent }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { handleKeyboardNotification($0) }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { handleKeyboardNotification($0) }
        .onAppear {
            if !llmService.isModelReady && !llmService.isLoadingModel {
                llmService.initializeAndLoadModel()
            }
            _ = userData.loadData()
            if llmService.activeSwiftDataSession == nil {
                self.hasMadeFirstSubmission = false
            } else {
                self.hasMadeFirstSubmission = !llmService.conversation.isEmpty
            }
        }
        .onChange(of: llmService.isLoadingResponse) { _, isLoading in
            handleGlowStateChange(isLoading: isLoading)
        }
        .onChange(of: llmService.activeSwiftDataSession?.id) { oldSessionId, newSessionId in
            if newSessionId == nil {
                self.hasMadeFirstSubmission = false
                self.promptText = ""
            } else {
                self.hasMadeFirstSubmission = !llmService.conversation.isEmpty
                if oldSessionId != nil && oldSessionId != newSessionId {
                     self.promptText = ""
                }
            }
        }
        .alert("Coming Soon!", isPresented: $showComingSoonAlert) { Button("OK") { } } message: { Text("This feature will be available in a future update with Gemma 3.") }
    }

    private var loadingIndicatorView: some View {
        VStack {
            ProgressView().progressViewStyle(CircularProgressViewStyle(tint: Color.sl_textPrimary)).scaleEffect(1.5)
            Text("Initializing Lumi...").font(.custom(nasalizationFont, size: 18)).foregroundColor(Color.sl_textSecondary).padding(.top, 10)
        }
    }

    private func errorStateView(message: String) -> some View {
        VStack {
            Spacer()
            errorWarningView(message: message)
            Button("Retry Initialization") { llmService.initializeAndLoadModel() }
                .font(.custom(nasalizationFont, size: 16)).padding()
                .foregroundColor(Color.sl_textOnAccent).background(Color.sl_bgAccent).cornerRadius(8)
            Spacer()
        }.padding()
    }

    private var mainContentVStack: some View {
        VStack(spacing: 0) {
            if let nonCriticalError = llmService.initErrorMessage, llmService.isModelReady {
                errorWarningView(message: nonCriticalError)
            } else if llmService.isLoadingModel && !llmService.isModelReady {
                Text("Lumi is initializing...")
                    .font(.custom(messageFontName, size: 13))
                    // ... (rest of this text view as before)
            }

            // ---- MODIFIED "NEW CHAT" DISPLAY ----
            if llmService.activeSwiftDataSession == nil &&
               llmService.conversation.isEmpty &&
               !llmService.isLoadingResponse {
                // Display nothing in the main content area above the input bar for a new chat.
                // The Spacer will push the inputAreaView to the bottom.
                Spacer()
            } else {
                // Show conversation list (it will be empty if conversation array is empty but session just started)
                conversationListViewContainer
                    .frame(maxHeight: .infinity)
                    .padding(EdgeInsets(top: 15, leading: 8, bottom: 4, trailing: 8))
            }
            // ---- END OF MODIFIED DISPLAY ----

            inputAreaView()
                .padding(.top, 3)
                .padding(.horizontal, 8)
                .padding(.bottom, keyboard.currentHeight > 0 ? 0 : 8)
        }
        .padding(.bottom, keyboard.currentHeight)
        .animation(Animation.customSpring(duration: keyboardAnimationDuration, bounce: 0.1), value: keyboard.currentHeight)
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private var conversationListViewContainer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.sl_bgPrimary)
                .shadow(color: Color.sl_glowColor.opacity(glowOpacity * 0.7),
                        radius: glowOpacity > 0.05 ? 10 : 0, x: 0, y: 0)
            ScrollViewReader { scrollViewProxy in
                buildScrollView(with: scrollViewProxy, isPromptFocused: self.isPromptFocused, keyboardAnimationDuration: self.keyboardAnimationDuration)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sl_glowColor.opacity(glowOpacity * 0.85),
                        lineWidth: glowOpacity > 0.05 ? 1.5 : 0)
                .allowsHitTesting(false)
            VStack {
                Rectangle().frame(height: 0.3).foregroundColor(Color.gray.opacity(0.35)).padding(.horizontal, 12)
                Spacer()
            }
        }
        .onChange(of: conversationGlowState) { oldGlowState, newGlowState in
            switch newGlowState {
            case .idle: withAnimation(.easeInOut(duration: 0.4)) { self.glowOpacity = 0.0 }
            case .pulsing:
                let minOpacity: Double = 0.15; self.glowOpacity = minOpacity
                DispatchQueue.main.async {
                    if self.conversationGlowState == .pulsing {
                        withAnimation(Animation.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { self.glowOpacity = 1.0 }
                    }
                }
            case .finalPulse:
                withAnimation(Animation.easeInOut(duration: 0.6)) { self.glowOpacity = 0.8 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { if self.conversationGlowState == .finalPulse { self.conversationGlowState = .fadingOut } }
            case .fadingOut:
                withAnimation(Animation.easeInOut(duration: 0.7)) { self.glowOpacity = 0.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { if self.conversationGlowState == .fadingOut { self.conversationGlowState = .idle } }
            }
        }
    }

    @ViewBuilder
    private func buildScrollView(with srcollViewProxy: ScrollViewProxy, isPromptFocused: Bool, keyboardAnimationDuration: TimeInterval) -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(llmService.conversation) { message in
                    MessageView(message: message).id(message.id)
                        .padding(.horizontal, 7)
                }
            }
            .padding(.horizontal, 0).padding(.top, 10)
        }
        .onTapGesture { self.hideKeyboard() }
        .onChange(of: llmService.conversation) { oldConversation, newConversation in
            scrollToBottom(proxy: srcollViewProxy, newConversation: newConversation, animationDuration: keyboardAnimationDuration)
        }
        .onChange(of: isPromptFocused) { _, newIsFocused in
             if newIsFocused {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    if let lastMessage = llmService.conversation.last {
                        withAnimation(Animation.customSpring(duration: keyboardAnimationDuration, bounce: 0.1)) {
                            srcollViewProxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func inputAreaView() -> some View {
        let isSubmitVisualState = !llmService.isLoadingResponse; let isButtonStopping = llmService.isLoadingResponse && currentPromptCanBeStopped()
        HStack(alignment: .bottom, spacing: 10) {
            HStack(alignment: .center, spacing: 5) {
                ZStack(alignment: .leading) {
                    GrowingTextEditor(text: $promptText, height: $textEditorHeight, maxHeight: 120, minHeight: collapsedMinHeight)
                        .frame(height: textEditorHeight)
                        .disabled(llmService.isLoadingResponse)
                        .focused($isPromptFocused)
                        .onSubmit(submitPrompt)
                    if promptText.isEmpty && !isPromptFocused {
                        Text(placeholderText).font(.custom(nasalizationFont, size: 16)).foregroundColor(Color.sl_textPlaceholder).padding(.leading, 9).padding(.trailing, 40).padding(.vertical, 10).allowsHitTesting(false).transition(.opacity.animation(.easeInOut(duration: 0.15)))
                    }
                }.layoutPriority(1)
                Menu { Button("Add Photos") { showComingSoonAlert = true }; Button("Activate Voice Mode") { showComingSoonAlert = true } } label: { Image(systemName: "plus").font(.system(size: 20, weight: .medium)).foregroundColor(Color.sl_textPrimary.opacity(0.8)).frame(width: 30, height: textEditorHeight).contentShape(Rectangle()) }.disabled(llmService.isLoadingResponse)
            }.padding(.horizontal, 6).padding(.vertical, 0).frame(minHeight: collapsedMinHeight).background(Color.sl_bgTertiary).cornerRadius(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(isSubmitVisualState ? Color.sl_glowColor.opacity(0.8) : Color.sl_borderPrimary, lineWidth: isSubmitVisualState ? 1.5 : 1)).shadow(color: isSubmitVisualState ? Color.sl_glowColor.opacity(0.6) : .clear, radius: isSubmitVisualState ? 6 : 0).layoutPriority(1)
            Button(action: submitOrStop) {
                ZStack {
                    if isButtonStopping { Image(systemName: "square.fill").font(.system(size: 18, weight: .medium))
                    } else if llmService.isLoadingResponse { DotLoadingView(color: Color.sl_textOnAccent, dotSize: 6, spacing: 3)
                    } else { Image(systemName: "arrow.up.circle.fill").font(.system(size: 20, weight: .medium)) }
                }.foregroundColor(Color.sl_textOnAccent)
            }
            .frame(width: 44, height: 44).background(isButtonStopping ? stopButtonRed : Color.sl_bgAccent).clipShape(Circle()).shadow(color: isButtonStopping ? stopButtonRedShadow : (isSubmitVisualState ? Color.sl_glowColor.opacity(0.6) : .clear), radius: 5, x: 0, y: 2)
            .disabled(
                (promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !llmService.isLoadingResponse) ||
                (!llmService.isModelReady && !llmService.isLoadingResponse)
            )
            .animation(llmService.isLoadingResponse ? .easeInOut(duration: 0.3) : .easeInOut(duration: 0.3).delay(0.5), value: llmService.isLoadingResponse)
        }.animation(.easeInOut(duration: 0.25), value: textEditorHeight)
    }

    @ToolbarContentBuilder
    private var navigationBarToolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { isPromptFocused = false }.font(.custom(nasalizationFont, size: 15)).foregroundColor(Color.sl_textPrimary) }
        ToolbarItem(placement: .navigationBarTrailing) {
            Button {
                llmService.startNewChat(context: modelContext)
            } label: {
                Image(systemName: "plus.bubble.fill").foregroundColor(Color.sl_textPrimary).font(.system(size: 17, weight: .medium))
            }
        }
    }

    private func errorWarningView(message: String) -> some View {
        Text(message).font(.custom(messageFontName, size: 14)).foregroundColor(Color.sl_errorText).padding().frame(maxWidth: .infinity).background(Color.sl_errorBg.opacity(0.15)).cornerRadius(8).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.sl_errorText.opacity(0.5), lineWidth: 1)).padding(.horizontal).padding(.top, 5)
    }

    private var placeholderText: String {
        let name = userData.userName; let defaultName = "Human"; let currentName = name.isEmpty ? defaultName : name
        if llmService.isLoadingModel { return "Lumi is waking up..." }
        else if !llmService.isModelReady && llmService.initErrorMessage == nil { return "Preparing Lumi..." }
        else if !llmService.isModelReady && llmService.initErrorMessage != nil { return "Lumi has an issue. See above." }
        else if !hasMadeFirstSubmission { return "Hi \(currentName), what's up?" } // This still drives the input placeholder
        else { return "Ask Lumi..." }
    }

    private func submitOrStop() {
        if llmService.isLoadingResponse { if currentPromptCanBeStopped() { llmService.stopGeneration(); if isPromptFocused { isPromptFocused = false } } } else { submitPrompt() }
    }

    private func submitPrompt() {
        let trimmedPrompt = promptText.trimmingCharacters(in: .whitespacesAndNewlines); guard !trimmedPrompt.isEmpty else { return }
        let textToSend = trimmedPrompt
        self.promptText = ""
        if isPromptFocused { isPromptFocused = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + (keyboard.currentHeight > 0 ? keyboardAnimationDuration * 0.25 : 0) + 0.05) {
            self.llmService.generateResponseStreaming(prompt: textToSend, context: modelContext)
            if !self.hasMadeFirstSubmission {
                self.hasMadeFirstSubmission = true
            }
        }
    }

    private func currentPromptCanBeStopped() -> Bool { return llmService.isLoadingResponse }
    private func handleKeyboardNotification(_ notification: Notification) {
        if let anim = KeyboardResponder.keyboardAnimation(from: notification) { self.keyboardAnimationDuration = anim.duration; self.keyboardAnimationCurve = anim.curve }
    }
    private func handleGlowStateChange(isLoading: Bool) {
        if isLoading { if conversationGlowState != .pulsing { conversationGlowState = .pulsing } } else { if conversationGlowState == .pulsing { conversationGlowState = .finalPulse } else { conversationGlowState = .idle } }
    }
    private func scrollToBottom(proxy: ScrollViewProxy, newConversation: [ChatMessage], animationDuration: TimeInterval) {
        if let lastMessage = newConversation.last {
            let animation = Animation.customSpring(duration: animationDuration, bounce: 0.1)
            withAnimation(animation) { proxy.scrollTo(lastMessage.id, anchor: .bottom) }
        }
    }
}

extension Animation {
    static func customSpring(duration: TimeInterval, bounce: CGFloat = 0.0) -> Animation {
        return .timingCurve(0.45, 1.05, 0.35, 1.0, duration: duration)
    }
}
    
#Preview {
    NavigationView {
        ChatView()
            .environmentObject(LlmInferenceService())
            .environmentObject(UserData.shared)
            .modelContainer(for: [ConversationSession.self, ChatMessageModel.self], inMemory: true)
            .preferredColorScheme(.dark)
    }
}
