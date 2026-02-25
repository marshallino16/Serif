import SwiftUI

struct OnboardingView: View {
    @Binding var isSignedIn: Bool
    @StateObject private var authViewModel = AuthViewModel()
    @State private var isSigningIn = false
    @State private var signInError: String?

    // Animation states - text
    @State private var showTopLine = false
    @State private var showSerif = false
    @State private var showBottomLine = false
    @State private var showButton = false
    @State private var serifScale: CGFloat = 0.85

    // Animation states - ambient light orbs
    @State private var orb1Offset: CGSize = CGSize(width: -120, height: -80)
    @State private var orb2Offset: CGSize = CGSize(width: 150, height: 60)
    @State private var orb3Offset: CGSize = CGSize(width: -40, height: 120)
    @State private var orb4Offset: CGSize = CGSize(width: 80, height: -140)
    @State private var orbsVisible = false

    var body: some View {
        ZStack {
            // MARK: - Deep black background
            Color(hex: "#010409")
                .ignoresSafeArea()

            // MARK: - Ambient light orbs (moving behind content)
            ambientLights

            // MARK: - Content
            VStack(spacing: 0) {
                Spacer()

                // Headline
                HStack(alignment: .center, spacing: 0) {
                    Text("THERE'S A NEW")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#8B949E"))
                        .tracking(11 * 0.09)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 20)
                        .opacity(showTopLine ? 1 : 0)
                        .offset(x: showTopLine ? 0 : -10)

                    Text("Serif")
                        .font(.custom("PPLocomotiveNew-Light", size: 96))
                        .foregroundColor(.white)
                        .opacity(showSerif ? 1 : 0)
                        .scaleEffect(serifScale)

                    Text("IN TOWN")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#8B949E"))
                        .tracking(11 * 0.09)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 20)
                        .opacity(showBottomLine ? 1 : 0)
                        .offset(x: showBottomLine ? 0 : 10)
                }

                Spacer().frame(height: 48)

                // Google Sign-In button
                Button {
                    Task { await handleSignIn() }
                } label: {
                    HStack(spacing: 12) {
                        if isSigningIn {
                            ProgressView()
                                .scaleEffect(0.7)
                                .tint(Color(hex: "#4285F4"))
                        } else {
                            Text("G")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundColor(Color(hex: "#4285F4"))
                        }
                        Text(isSigningIn ? "Signing in…" : "Sign in with Google")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "#1C1C1E"))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .frame(minWidth: 220)
                    .background(Color.white.opacity(isSigningIn ? 0.8 : 1))
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 20)

                if let error = signInError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#FF6B6B"))
                        .multilineTextAlignment(.center)
                        .padding(.top, 8)
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
            // Orb 1 — large blue, slow drift
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#58A6FF").opacity(0.35), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 220
                    )
                )
                .frame(width: 450, height: 450)
                .offset(orb1Offset)
                .blur(radius: 80)

            // Orb 2 — purple/indigo accent
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#A371F7").opacity(0.28), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 180
                    )
                )
                .frame(width: 380, height: 380)
                .offset(orb2Offset)
                .blur(radius: 70)

            // Orb 3 — green accent
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#3FB950").opacity(0.20), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 160
                    )
                )
                .frame(width: 320, height: 320)
                .offset(orb3Offset)
                .blur(radius: 60)

            // Orb 4 — blue accent
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#58A6FF").opacity(0.24), Color.clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: 200
                    )
                )
                .frame(width: 400, height: 400)
                .offset(orb4Offset)
                .blur(radius: 90)
        }
        .opacity(orbsVisible ? 1 : 0)
    }

    // MARK: - Animation Sequence

    private func runAnimationSequence() {
        // Fade in ambient lights
        withAnimation(.easeIn(duration: 1.5)) {
            orbsVisible = true
        }

        // Start orb drift loops
        startOrbAnimations()

        // Text reveal sequence
        withAnimation(.easeOut(duration: 0.6).delay(0.6)) {
            showTopLine = true
        }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.75).delay(1.0)) {
            showSerif = true
            serifScale = 1.0
        }
        withAnimation(.easeOut(duration: 0.6).delay(1.5)) {
            showBottomLine = true
        }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(2.1)) {
            showButton = true
        }
    }

    private func startOrbAnimations() {
        withAnimation(.easeInOut(duration: 8).repeatForever(autoreverses: true)) {
            orb1Offset = CGSize(width: 100, height: 60)
        }
        withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true).delay(0.5)) {
            orb2Offset = CGSize(width: -130, height: -80)
        }
        withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true).delay(1.0)) {
            orb3Offset = CGSize(width: 80, height: -100)
        }
        withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true).delay(0.3)) {
            orb4Offset = CGSize(width: -100, height: 100)
        }
    }

    // MARK: - Sign In

    private func handleSignIn() async {
        isSigningIn  = true
        signInError  = nil
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
                window.backgroundColor = NSColor(red: 0.004, green: 0.016, blue: 0.035, alpha: 1)
            }
        }
    }
}
