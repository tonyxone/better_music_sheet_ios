import SwiftUI

/// The account screen — reached from the library toolbar's person icon (see
/// LibraryView). Sign-in is optional everywhere else in the app; uploading,
/// annotating and practising all work as a guest. This is the one screen
/// that's about identity rather than sheet music.
struct AccountView: View {
    @State private var model = AccountModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.paper.ignoresSafeArea()
                content
            }
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task { await model.load() }
        // A brief pause so "Signed in as X" is actually visible for a beat,
        // rather than the screen vanishing the instant it appears — but only
        // for a sign-in that just happened, never for opening the screen to
        // look at an account you were already signed into (see
        // AccountModel.justSignedIn).
        .onChange(of: model.justSignedIn) { _, justSignedIn in
            guard justSignedIn else { return }
            Task {
                try? await Task.sleep(for: .seconds(0.6))
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .checking:
            ProgressView().tint(Brand.accent)
        case .signedOut:
            SignInForm(model: model)
        case .signedIn(let user):
            SignedInContent(user: user, model: model)
        }
    }
}

private struct SignedInContent: View {
    let user: User
    let model: AccountModel

    @State private var showingDeleteConfirmation = false
    @State private var deleteConfirmationText = ""
    @State private var deleting = false
    @State private var deleteError: String?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(Brand.accent)

            VStack(spacing: 4) {
                Text(user.displayName ?? user.email ?? "Signed in")
                    .font(Brand.title(20))
                    .foregroundStyle(Brand.ink)
                if let email = user.email, user.displayName != nil {
                    Text(email)
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.inkSoft)
                }
            }

            Spacer()

            if deleting {
                ProgressView().tint(Brand.danger)
            } else {
                if let deleteError {
                    Text(deleteError)
                        .font(.system(size: 12.5))
                        .foregroundStyle(Brand.danger)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button("Sign out") {
                    Task { await model.signOut() }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Brand.danger)

                Button("Delete account") {
                    deleteConfirmationText = ""
                    deleteError = nil
                    showingDeleteConfirmation = true
                }
                .font(.system(size: 13))
                .foregroundStyle(Brand.inkSoft)
                .padding(.bottom, 24)
            }
        }
        // A native alert with a text field, rather than reproducing the web
        // app's bespoke confirmation modal — same friction (typing "delete"
        // to enable the button), the platform's own idiom for it.
        .alert("Delete your account?", isPresented: $showingDeleteConfirmation) {
            TextField("Type \"delete\" to confirm", text: $deleteConfirmationText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Delete Account", role: .destructive) {
                Task { await confirmDelete() }
            }
            .disabled(deleteConfirmationText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != "delete")
        } message: {
            Text("This permanently deletes your account\(user.email.map { " (\($0))" } ?? "") and your sheet history. This can't be undone.")
        }
    }

    private func confirmDelete() async {
        deleting = true
        defer { deleting = false }
        do {
            try await model.deleteAccount()
        } catch {
            deleteError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Sign-in form

/// Which step of the flow the form is showing. Sign-up and password reset
/// both end at a code-entry step, so they're separate steps rather than one
/// generic one — the copy and the next action differ. Mirrors the web app's
/// sign-in-modal.tsx.
private enum AuthStep: Sendable {
    case signIn, signUp, confirm, forgot, reset
}

private struct SignInForm: View {
    let model: AccountModel

    @State private var step: AuthStep = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var name = ""
    @State private var code = ""
    @State private var errorMessage: String?
    @State private var notice: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 6) {
                    Text(title)
                        .font(Brand.title(22))
                        .foregroundStyle(Brand.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Brand.inkSoft)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 24)

                if let notice {
                    Text(notice)
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.inkSoft)
                        .multilineTextAlignment(.center)
                }
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(Brand.danger)
                        .multilineTextAlignment(.center)
                }

                fields
                    .disabled(model.busy)

                Button(action: submit) {
                    Text(submitLabel)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Brand.accent, in: .capsule)
                        .opacity(model.busy ? 0.6 : 1)
                }
                .disabled(model.busy)

                // Only on the sign-in step: a federated provider creates the
                // pool user itself on first use, the same way it signs one in
                // on every later use — there's no separate "create account"
                // step for it.
                if step == .signIn, model.isAuthConfigured, !model.availableProviders.isEmpty {
                    HStack(spacing: 10) {
                        Rectangle().fill(Brand.hairline).frame(height: 1)
                        Text("or").font(.system(size: 12)).foregroundStyle(Brand.inkSoft)
                        Rectangle().fill(Brand.hairline).frame(height: 1)
                    }
                    VStack(spacing: 12) {
                        ForEach(model.availableProviders, id: \.self) { provider in
                            SocialSignInButton(provider: provider, busy: model.busyProvider == provider) {
                                signIn(with: provider)
                            }
                            .disabled(model.busyProvider != nil || model.busy)
                        }
                    }
                }

                links
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    @ViewBuilder
    private var fields: some View {
        VStack(spacing: 14) {
            if step == .signIn || step == .signUp || step == .forgot {
                FormField(label: "Email") {
                    TextField("", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }

            if step == .signUp {
                FormField(label: "Display name") {
                    TextField("", text: $name)
                        .textContentType(.name)
                }
            }

            if step == .confirm || step == .reset {
                FormField(label: "Code") {
                    TextField("", text: $code)
                        .textContentType(.oneTimeCode)
                        .keyboardType(.numberPad)
                }
            }

            if step != .forgot, step != .confirm {
                FormField(label: step == .reset ? "New password" : "Password") {
                    SecureField("", text: $password)
                        .textContentType(step == .signIn ? .password : .newPassword)
                }
                if step != .signIn {
                    Text("At least 8 characters, with a number, an uppercase and a lowercase letter.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Brand.inkSoft)
                }
            }
        }
    }

    @ViewBuilder
    private var links: some View {
        switch step {
        case .signIn:
            HStack {
                Button("Forgot password?") { go(.forgot) }
                Spacer()
                Button("Create an account") { go(.signUp) }
            }
            .font(.system(size: 13))
            .foregroundStyle(Brand.accent)
        case .signUp, .forgot:
            Button("Back to sign in") { go(.signIn) }
                .font(.system(size: 13))
                .foregroundStyle(Brand.accent)
        case .confirm:
            Button("Resend code") {
                Task {
                    do { try await model.resendConfirmationCode(email: email); notice = "Sent — check your email again." }
                    catch { errorMessage = describe(error) }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Brand.accent)
        case .reset:
            Button("Back to sign in") { go(.signIn) }
                .font(.system(size: 13))
                .foregroundStyle(Brand.accent)
        }
    }

    private var title: String {
        switch step {
        case .signIn: "Sign in"
        case .signUp: "Create an account"
        case .confirm: "Check your email"
        case .forgot: "Reset your password"
        case .reset: "Choose a new password"
        }
    }

    private var subtitle: String? {
        switch step {
        case .confirm: "Enter the code we sent to \(email)."
        case .forgot: "We'll email you a code to set a new password."
        default: nil
        }
    }

    private var submitLabel: String {
        switch step {
        case .signIn: model.busy ? "Signing in…" : "Sign in"
        case .signUp: model.busy ? "Creating…" : "Create account"
        case .confirm: model.busy ? "Confirming…" : "Confirm"
        case .forgot: model.busy ? "Sending…" : "Send reset code"
        case .reset: model.busy ? "Saving…" : "Save and sign in"
        }
    }

    private func go(_ next: AuthStep, notice: String? = nil) {
        step = next
        errorMessage = nil
        self.notice = notice
    }

    private func signIn(with provider: SocialProvider) {
        errorMessage = nil
        Task {
            do { try await model.signIn(with: provider) }
            catch let error as AuthError { if case .cancelled = error {} else { errorMessage = error.errorDescription } }
            catch { errorMessage = error.localizedDescription }
        }
    }

    /// Mirrors sign-in-modal.tsx's handleSubmit — one action per step, each
    /// ending either at the signed-in state or the next step in the flow.
    private func submit() {
        guard !model.busy else { return }
        errorMessage = nil

        switch step {
        case .signIn:
            Task {
                do {
                    try await model.signIn(email: email, password: password)
                } catch let error as CognitoError where error.code == "UserNotConfirmedException" {
                    // Signing in before confirming the emailed code is common
                    // enough to route straight to the code step instead of a
                    // dead end.
                    try? await model.resendConfirmationCode(email: email)
                    go(.confirm, notice: "Your account isn't confirmed yet — we've sent you a new code.")
                } catch {
                    errorMessage = describe(error)
                }
            }

        case .signUp:
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                errorMessage = "Please enter a display name."
                return
            }
            Task {
                do {
                    let needsCode = try await model.signUp(email: email, password: password, name: name)
                    if needsCode {
                        go(.confirm, notice: "We've emailed you a confirmation code.")
                    } else {
                        try await model.signIn(email: email, password: password)
                    }
                } catch {
                    errorMessage = describe(error)
                }
            }

        case .confirm:
            Task {
                do {
                    try await model.confirmSignUp(email: email, code: code)
                    try await model.signIn(email: email, password: password)
                } catch {
                    errorMessage = describe(error)
                }
            }

        case .forgot:
            Task {
                do {
                    try await model.forgotPassword(email: email)
                    go(.reset, notice: "We've emailed you a reset code.")
                } catch {
                    errorMessage = describe(error)
                }
            }

        case .reset:
            Task {
                do {
                    try await model.confirmForgotPassword(email: email, code: code, newPassword: password)
                    try await model.signIn(email: email, password: password)
                } catch {
                    errorMessage = describe(error)
                }
            }
        }
    }

    /// Cognito's raw messages are mostly fine, but a few are cryptic or leak
    /// more than they should — matches sign-in-modal.tsx's describe().
    private func describe(_ error: Error) -> String {
        guard let cognitoError = error as? CognitoError else {
            return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        switch cognitoError.code {
        case "NotAuthorizedException", "UserNotFoundException":
            return "Incorrect email or password."
        case "UsernameExistsException":
            return "An account with that email already exists."
        case "CodeMismatchException":
            return "That code doesn't match. Check it and try again."
        case "ExpiredCodeException":
            return "That code has expired — request a new one."
        case "LimitExceededException":
            return "Too many attempts. Wait a few minutes and try again."
        case "InvalidPasswordException":
            return "That password doesn't meet the requirements below."
        case "UserNotConfirmedException":
            return "This account still needs the emailed confirmation code."
        default:
            return cognitoError.message
        }
    }
}

/// A labelled text field in the app's paper/ink style — the first text input
/// in the app, so this establishes the convention rather than following one.
private struct FormField<Content: View>: View {
    let label: String
    let content: Content

    init(label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(Brand.inkSoft)
            content
                .font(.system(size: 15))
                .foregroundStyle(Brand.ink)
                .padding(.horizontal, 12)
                .frame(height: 44)
                .background(Brand.card, in: .rect(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Brand.hairline, lineWidth: 1))
        }
    }
}

/// One social provider's button. "Sign in with X" is the sanctioned phrasing
/// for both providers, matching the web app's sign-in-modal.tsx.
private struct SocialSignInButton: View {
    let provider: SocialProvider
    let busy: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if busy {
                    ProgressView().tint(foreground)
                } else {
                    icon
                }
                Text(provider.displayLabel)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(background, in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var icon: some View {
        switch provider {
        case .google:
            Text("G")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Color(red: 0.259, green: 0.522, blue: 0.957))
                .frame(width: 20, height: 20)
        case .signInWithApple:
            Image(systemName: "apple.logo")
                .font(.system(size: 16))
                .frame(width: 20, height: 20)
        }
    }

    private var background: Color {
        provider == .signInWithApple ? Brand.ink : Brand.card
    }
    private var foreground: Color {
        provider == .signInWithApple ? .white : Brand.ink
    }
    private var border: Color {
        provider == .signInWithApple ? .clear : Brand.hairline
    }
}

#Preview {
    AccountView()
}
