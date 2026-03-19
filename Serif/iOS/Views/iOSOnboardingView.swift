import SwiftUI

struct iOSOnboardingView: View {
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
    @State private var orb1Offset: CGSize = CGSize(width: -100, height: -80)
    @State private var orb2Offset: CGSize = CGSize(width: 120, height: 60)
    @State private var orb3Offset: CGSize = CGSize(width: -40, height: 100)
    @State private var orbsVisible = false

    var body: some View {
        ZStack {
            Color(hex: "#010409")
                .ignoresSafeArea()

            ambientLights

            VStack(spacing: 0) {
                Spacer()

                // Logo: Ser [icon] f
                VStack(spacing: 8) {
                    HStack(alignment: .center, spacing: 0) {
                        Text("Ser")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(showSer ? 1 : 0)
                            .offset(x: showSer ? 0 : 20)

                        Image("SerifLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(height: 42)
                            .opacity(showIcon ? 1 : 0)
                            .scaleEffect(iconScale)
                            .rotationEffect(.degrees(iconRotation))
                            .offset(y: iconDrop)
                            .padding(.horizontal, -2)

                        Text("f")
                            .font(.system(size: 56, weight: .bold))
                            .foregroundColor(.white)
                            .opacity(showF ? 1 : 0)
                            .offset(x: showF ? 0 : -20)
                    }

                    Text("THERE'S A NEW SHERIFF IN TOWN")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.white.opacity(0.5))
                        .tracking(3)
                        .opacity(showTaglineBottom ? 1 : 0)
                        .offset(y: showTaglineBottom ? 0 : -8)
                }

                Spacer().frame(height: 60)

                // Sign-in button
                Button {
                    Task { await handleSignIn() }
                } label: {
                    HStack(spacing: 12) {
                        Group {
                            if isSigningIn {
                                ProgressView()
                                    .tint(Color(hex: "#1C1C1E"))
                            } else {
                                GoogleLogo()
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .frame(width: 20, height: 20)
                        Text(isSigningIn ? "Signing in\u{2026}" : "Continue with Google")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundColor(Color(hex: "#1C1C1E"))
                    }
                    .padding(.horizontal, 28)
                    .padding(.vertical, 14)
                    .frame(minWidth: 260)
                    .background(
                        Capsule().fill(.white)
                    )
                    .overlay(
                        Capsule().stroke(Color(hex: "#DADCE0"), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSigningIn)
                .opacity(showButton ? 1 : 0)
                .offset(y: showButton ? 0 : 24)

                if let error = signInError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 12)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onAppear { runAnimationSequence() }
    }

    // MARK: - Ambient Lights

    private var ambientLights: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#58A6FF").opacity(0.35), .clear],
                        center: .center, startRadius: 0, endRadius: 180
                    )
                )
                .frame(width: 380, height: 380)
                .offset(orb1Offset)
                .blur(radius: 70)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#A371F7").opacity(0.28), .clear],
                        center: .center, startRadius: 0, endRadius: 150
                    )
                )
                .frame(width: 320, height: 320)
                .offset(orb2Offset)
                .blur(radius: 60)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(hex: "#3FB950").opacity(0.20), .clear],
                        center: .center, startRadius: 0, endRadius: 120
                    )
                )
                .frame(width: 260, height: 260)
                .offset(orb3Offset)
                .blur(radius: 50)
        }
        .opacity(orbsVisible ? 1 : 0)
    }

    // MARK: - Animations

    private func runAnimationSequence() {
        withAnimation(.easeIn(duration: 1.8)) { orbsVisible = true }
        startOrbAnimations()
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(0.5)) { showSer = true }
        withAnimation(.spring(response: 0.7, dampingFraction: 0.55).delay(0.9)) {
            showIcon = true; iconDrop = 0; iconRotation = 0; iconScale = 1.0
        }
        withAnimation(.spring(response: 0.6, dampingFraction: 0.8).delay(1.2)) { showF = true }
        withAnimation(.easeOut(duration: 0.5).delay(1.6)) { showTaglineTop = true }
        withAnimation(.easeOut(duration: 0.5).delay(1.8)) { showTaglineBottom = true }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.8).delay(2.3)) { showButton = true }
    }

    private func startOrbAnimations() {
        withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) {
            orb1Offset = CGSize(width: 90, height: 60)
        }
        withAnimation(.easeInOut(duration: 11).repeatForever(autoreverses: true).delay(0.5)) {
            orb2Offset = CGSize(width: -100, height: -70)
        }
        withAnimation(.easeInOut(duration: 10).repeatForever(autoreverses: true).delay(1.0)) {
            orb3Offset = CGSize(width: 60, height: -80)
        }
    }

    // MARK: - Sign In

    private func handleSignIn() async {
        isSigningIn = true
        signInError = nil
        await authViewModel.signIn()
        isSigningIn = false
        if authViewModel.hasAccounts {
            withAnimation(.easeInOut(duration: 0.5)) { isSignedIn = true }
        } else {
            signInError = authViewModel.error ?? "Sign-in failed. Please try again."
        }
    }
}
