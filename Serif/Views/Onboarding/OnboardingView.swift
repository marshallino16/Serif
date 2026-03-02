import SwiftUI

struct OnboardingView: View {
    @Binding var isSignedIn: Bool
    @StateObject private var authViewModel = AuthViewModel()
    @State private var isSigningIn = false
    @State private var signInError: String?

    // Animation states
    @State private var showTaglineTop = false
    @State private var showSer = false
    @State private var showIcon = false
    @State private var iconDrop: CGFloat = -40
    @State private var showF = false
    @State private var showTaglineBottom = false
    @State private var showButton = false
    @State private var iconRotation: Double = -12
    @State private var iconScale: CGFloat = 0.3

    // Ambient orbs
    @State private var orb1Offset: CGSize = CGSize(width: -140, height: -100)
    @State private var orb2Offset: CGSize = CGSize(width: 160, height: 80)
    @State private var orb3Offset: CGSize = CGSize(width: -60, height: 140)
    @State private var orbsVisible = false

    // Logo colors
    private let coral = Color(red: 0.94, green: 0.44, blue: 0.44)   // #F07070
    private let blue  = Color(red: 0.42, green: 0.61, blue: 0.96)   // #6B9BF5

    var body: some View {
        ZStack {
            // MARK: - Deep black background
            Color(hex: "#010409")
                .ignoresSafeArea()

            // Ambient lights — logo colors
            ambientLights

            // Content
            VStack(spacing: 0) {
                Spacer()

                // Headline
                HStack(alignment: .center, spacing: 0) {
                    Text("THERE'S A NEW")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(11 * 0.18)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 20)
                        .opacity(showTaglineTop ? 1 : 0)
                        .offset(x: showTaglineTop ? 0 : -10)

                    // Ser [icon] f
                    HStack(alignment: .center, spacing: 0) {
                        Text("Ser")
                            .font(.system(size: 80, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .opacity(showSer ? 1 : 0)
                            .offset(x: showSer ? 0 : 30)

                        Image("SerifLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 60)
                            .opacity(showIcon ? 1 : 0)
                            .scaleEffect(iconScale)
                            .rotationEffect(.degrees(iconRotation))
                            .offset(y: iconDrop)
                            .padding(.horizontal, -2)

                        Text("f")
                            .font(.system(size: 80, weight: .bold, design: .default))
                            .foregroundColor(.white)
                            .opacity(showF ? 1 : 0)
                            .offset(x: showF ? 0 : -30)
                    }

                    Text("IN TOWN")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(11 * 0.18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 20)
                        .opacity(showTaglineBottom ? 1 : 0)
                        .offset(x: showTaglineBottom ? 0 : 10)
                }
                    .opacity(showTaglineBottom ? 1 : 0)
                    .offset(y: showTaglineBottom ? 0 : -8)

                Spacer().frame(height: 56)

                // Google Sign-In button
                Button {
                    Task { await handleSignIn() }
                } label: {
                    HStack(spacing: 12) {
                        if isSigningIn {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(blue)
                        } else {
                            Text("G")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(blue)
                        }
                        Text(isSigningIn ? "Signing in\u{2026}" : "Sign in with Google")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "#1C1C1E"))
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .frame(minWidth: 230)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(.white)
                            .shadow(color: coral.opacity(0.25), radius: 20, y: 8)
                            .shadow(color: blue.opacity(0.2), radius: 30, y: 12)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 24)

                if let error = signInError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(coral)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                        .opacity(showButton ? 1 : 0)
                }

                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            runAnimationSequence()
            hideTrafficLights(true)
        }
        .onDisappear {
            hideTrafficLights(false)
        }
    }

    // MARK: - Ambient Lights

    private var ambientLights: some View {
        ZStack {
            // Coral orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#58A6FF").opacity(0.35), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 240
                    )
                )
                .frame(width: 500, height: 500)
                .offset(orb1Offset)
                .blur(radius: 90)

            // Blue orb
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#A371F7").opacity(0.28), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 420, height: 420)
                .offset(orb2Offset)
                .blur(radius: 80)

            // Subtle warm accent
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#3FB950").opacity(0.20), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 160
                    )
                )
                .frame(width: 340, height: 340)
                .offset(orb3Offset)
                .blur(radius: 70)
        }
        .opacity(orbsVisible ? 1 : 0)
    }

    // MARK: - Animation Sequence

    private func runAnimationSequence() {
        // 1. Ambient orbs fade in
        withAnimation(.easeIn(duration: 1.8)) {
            orbsVisible = true
        }
        startOrbAnimations()

        // 2. "Ser" slides in from left
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5)) {
            showSer = true
        }

        // 3. Icon drops in with rotation + bounce
        withAnimation(.spring(response: 0.7, dampingFraction: 0.55).delay(0.9)) {
            showIcon = true
            iconDrop = 0
            iconRotation = 0
            iconScale = 1.0
        }

        // 4. "f" slides in from right
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.2)) {
            showF = true
        }

        // 5. Taglines
        withAnimation(.easeOut(duration: 0.5).delay(1.6)) {
            showTaglineTop = true
        }
        withAnimation(.easeOut(duration: 0.5).delay(1.8)) {
            showTaglineBottom = true
        }

        // 6. Button
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(2.3)) {
            showButton = true
        }
    }

    private func startOrbAnimations() {
        withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
            orb1Offset = CGSize(width: 120, height: 80)
        }
        withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true).delay(0.5)) {
            orb2Offset = CGSize(width: -140, height: -90)
        }
        withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true).delay(1.0)) {
            orb3Offset = CGSize(width: 90, height: -110)
        }
    }

    // MARK: - Sign In

    private func handleSignIn() async {
        isSigningIn = true
        signInError = nil
        await authViewModel.signIn()
        isSigningIn = false
        if authViewModel.hasAccounts {
            hideTrafficLights(false)
            withAnimation(.easeInOut(duration: 0.5)) {
                isSignedIn = true
            }
        } else {
            signInError = authViewModel.error ?? "Sign-in failed. Please try again."
        }
    }

    // MARK: - Window Chrome

    private func hideTrafficLights(_ hide: Bool) {
        DispatchQueue.main.async {
            guard let window = NSApplication.shared.windows.first else { return }
            window.standardWindowButton(.closeButton)?.isHidden = hide
            window.standardWindowButton(.miniaturizeButton)?.isHidden = hide
            window.standardWindowButton(.zoomButton)?.isHidden = hide
            if hide {
                window.toolbar = nil
                window.isMovableByWindowBackground = true
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.backgroundColor = NSColor(red: 0.031, green: 0.035, blue: 0.047, alpha: 1)
            }
        }
    }
}
