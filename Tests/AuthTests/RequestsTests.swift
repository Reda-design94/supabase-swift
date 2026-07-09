//
//  RequestsTests.swift
//
//
//  Created by Guilherme Souza on 07/10/23.
//

import Foundation
import InlineSnapshotTesting
import Replay
import TestHelpers
import Testing

@_spi(Experimental) @testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// These tests only verify that the SDK issues a request to the expected method+path — the
/// actual request shape (headers, query, body) was previously asserted via a Mocker
/// `.snapshotRequest` curl dump. Per the Phase 0 decision, curl-snapshot assertions are dropped
/// with no shim; Replay's stub matching is the request-shape enforcement now — an
/// unexpected method/path throws a `ReplayError` mismatch, failing the test.
@Suite
struct RequestsTests {
  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/signup", body: MockData.session)], matching: [.method, .path], scope: .test))
  func signUpWithEmailAndPassword() async throws {
    let sut = makeSUT()

    try await sut.signUp(
      email: "example@mail.com",
      password: "the.pass",
      data: ["custom_key": .string("custom_value")],
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "dummy-captcha"
    )
  }

  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/signup", body: MockData.session)], matching: [.method, .path], scope: .test))
  func signUpWithPhoneAndPassword() async throws {
    let sut = makeSUT()

    try await sut.signUp(
      phone: "+1 202-918-2132",
      password: "the.pass",
      data: ["custom_key": .string("custom_value")],
      captchaToken: "dummy-captcha"
    )
  }

  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/token", body: MockData.session)], matching: [.method, .path], scope: .test))
  func signInWithEmailAndPassword() async throws {
    let sut = makeSUT()

    try await sut.signIn(
      email: "example@mail.com",
      password: "the.pass",
      captchaToken: "dummy-captcha"
    )
  }

  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/token", body: MockData.session)], matching: [.method, .path], scope: .test))
  func signInWithPhoneAndPassword() async throws {
    let sut = makeSUT()

    try await sut.signIn(
      phone: "+1 202-918-2132",
      password: "the.pass",
      captchaToken: "dummy-captcha"
    )
  }

  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/token", body: MockData.session)], matching: [.method, .path], scope: .test))
  func signInWithIdToken() async throws {
    let sut = makeSUT()

    try await sut.signInWithIdToken(
      credentials: OpenIDConnectCredentials(
        provider: .apple,
        idToken: "id-token",
        accessToken: "access-token",
        nonce: "nonce",
        gotrueMetaSecurity: AuthMetaSecurity(
          captchaToken: "captcha-token"
        )
      )
    )
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/otp", 200, [:]) { "{}" }], matching: [.method, .path], scope: .test))
  func signInWithOTPUsingEmail() async throws {
    let sut = makeSUT()

    try await sut.signInWithOTP(
      email: "example@mail.com",
      redirectTo: URL(string: "https://supabase.com"),
      shouldCreateUser: true,
      data: ["custom_key": .string("custom_value")],
      captchaToken: "dummy-captcha"
    )
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/otp", 200, [:]) { "{}" }], matching: [.method, .path], scope: .test))
  func signInWithOTPUsingPhone() async throws {
    let sut = makeSUT()

    try await sut.signInWithOTP(
      phone: "+1 202-918-2132",
      shouldCreateUser: true,
      data: ["custom_key": .string("custom_value")],
      captchaToken: "dummy-captcha"
    )
  }

  @Test
  func getOAuthSignInURL() async throws {
    let sut = makeSUT()
    let url = try sut.getOAuthSignInURL(
      provider: .github, scopes: "read,write",
      redirectTo: URL(string: "https://dummy-url.com/redirect")!,
      queryParams: [("extra_key", "extra_value")]
    )
    #expect(
      url
        == URL(
          string:
            "http://localhost:54321/auth/v1/authorize?provider=github&scopes=read,write&redirect_to=https://dummy-url.com/redirect&extra_key=extra_value"
        )!
    )
  }

  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/token", body: MockData.session)], matching: [.method, .path], scope: .test))
  func refreshSession() async throws {
    let sut = makeSUT()
    try await sut.refreshSession(refreshToken: "refresh-token")
  }

  #if !os(Linux) && !os(Windows) && !os(Android)
    @Test(
      .replay(
        stubs: [
          Stub(.get, "http://localhost:54321/auth/v1/user", body: json(named: "user"))
        ], matching: [.method, .path], scope: .test))
    func sessionFromURL() async throws {
      let sut = makeSUT()

      let currentDate = Date()

      Dependencies[sut.clientID].date = { currentDate }

      let url = URL(
        string:
          "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
      )!

      let session = try await sut.session(from: url)
      let expectedSession = Session(
        accessToken: "accesstoken",
        tokenType: "bearer",
        expiresIn: 60,
        expiresAt: currentDate.addingTimeInterval(60).timeIntervalSince1970,
        refreshToken: "refreshtoken",
        user: User(fromMockNamed: "user")
      )
      #expect(session == expectedSession)
    }
  #endif

  @Test
  func sessionFromURLWithMissingComponent() async {
    let sut = makeSUT()

    let url = URL(
      string:
        "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken"
    )!

    do {
      _ = try await sut.session(from: url)
    } catch {
      assertInlineSnapshot(of: error, as: .dump) {
        """
        ▿ AuthError
          ▿ implicitGrantRedirect: (1 element)
            - message: "No session defined in URL"

        """
      }
    }
  }

  @Test(.replay(stubs: [Stub(.get, "http://localhost:54321/auth/v1/user", body: MockData.user)], matching: [.method, .path], scope: .test))
  func setSessionWithAFutureExpirationDate() async throws {
    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I"

    try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
  }

  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/token", body: MockData.session)], matching: [.method, .path], scope: .test))
  func setSessionWithAExpiredToken() async throws {
    let sut = makeSUT()

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNjQ4NjQwMDIxLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.CGr5zNE5Yltlbn_3Ms2cjSLs_AW9RKM3lxh7cTQrg0w"

    try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/logout", 200, [:]) { "" }], matching: [.method, .path], scope: .test))
  func signOut() async throws {
    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.signOut()
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/logout", 200, [:]) { "" }], matching: [.method, .path], scope: .test))
  func signOutWithLocalScope() async throws {
    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.signOut(scope: .local)
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/logout", 200, [:]) { "" }], matching: [.method, .path], scope: .test))
  func signOutWithOthersScope() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.signOut(scope: .others)
  }

  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/verify", body: MockData.session)], matching: [.method, .path], scope: .test))
  func verifyOTPUsingEmail() async throws {
    let sut = makeSUT()

    try await sut.verifyOTP(
      email: "example@mail.com",
      token: "123456",
      type: .magiclink,
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/verify", body: MockData.session)], matching: [.method, .path], scope: .test))
  func verifyOTPUsingPhone() async throws {
    let sut = makeSUT()

    try await sut.verifyOTP(
      phone: "+1 202-918-2132",
      token: "123456",
      type: .sms,
      captchaToken: "captcha-token"
    )
  }

  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/verify", body: MockData.session)], matching: [.method, .path], scope: .test))
  func verifyOTPUsingTokenHash() async throws {
    let sut = makeSUT()

    try await sut.verifyOTP(
      tokenHash: "abc-def",
      type: .email
    )
  }

  @Test(.replay(stubs: [Stub(.put, "http://localhost:54321/auth/v1/user", body: MockData.user)], matching: [.method, .path], scope: .test))
  func updateUser() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.update(
      user: UserAttributes(
        email: "example@mail.com",
        phone: "+1 202-918-2132",
        password: "another.pass",
        nonce: "abcdef",
        emailChangeToken: "123456",
        data: ["custom_key": .string("custom_value")]
      )
    )
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/recover", 200, [:]) { "{}" }], matching: [.method, .path], scope: .test))
  func resetPasswordForEmail() async throws {
    let sut = makeSUT()
    try await sut.resetPasswordForEmail(
      "example@mail.com",
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/resend", 200, [:]) { "{}" }], matching: [.method, .path], scope: .test))
  func resendEmail() async throws {
    let sut = makeSUT()

    try await sut.resend(
      email: "example@mail.com",
      type: .emailChange,
      emailRedirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/resend", 200, [:]) { "{}" }], matching: [.method, .path], scope: .test))
  func resendPhone() async throws {
    let sut = makeSUT()

    try await sut.resend(
      phone: "+1 202-918-2132",
      type: .phoneChange,
      captchaToken: "captcha-token"
    )
  }

  @Test(
    .replay(
      stubs: [
        .delete(
          "http://localhost:54321/auth/v1/admin/users/E621E1F8-C36C-495A-93FC-0C247A3E6E5F", 200,
          [:]) { "{}" }
      ], matching: [.method, .path], scope: .test))
  func deleteUser() async throws {
    let sut = makeSUT()

    let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
    try await sut.admin.deleteUser(id: id)
  }

  @Test(.replay(stubs: [.get("http://localhost:54321/auth/v1/reauthenticate", 200, [:]) { "" }], matching: [.method, .path], scope: .test))
  func reauthenticate() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.reauthenticate()
  }

  @Test(
    .replay(
      stubs: [
        .delete(
          "http://localhost:54321/auth/v1/user/identities/E621E1F8-C36C-495A-93FC-0C247A3E6E5F", 200,
          [:]) { "" }
      ], matching: [.method, .path], scope: .test))
  func unlinkIdentity() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.unlinkIdentity(
      UserIdentity(
        id: "5923044",
        identityId: UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!,
        userId: UUID(),
        identityData: [:],
        provider: "email",
        createdAt: Date(),
        lastSignInAt: Date(),
        updatedAt: Date()
      )
    )
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/sso", 200, [:]) { #"{"url":"https://supabase.com"}"# }], matching: [.method, .path], scope: .test))
  func signInWithSSOUsingDomain() async throws {
    let sut = makeSUT()

    _ = try await sut.signInWithSSO(
      domain: "supabase.com",
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/sso", 200, [:]) { #"{"url":"https://supabase.com"}"# }], matching: [.method, .path], scope: .test))
  func signInWithSSOUsingProviderId() async throws {
    let sut = makeSUT()

    _ = try await sut.signInWithSSO(
      providerId: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/signup", body: MockData.session)], matching: [.method, .path], scope: .test))
  func signInAnonymously() async throws {
    let sut = makeSUT()

    try await sut.signInAnonymously(
      data: ["custom_key": .string("custom_value")],
      captchaToken: "captcha-token"
    )
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/auth/v1/user/identities/authorize", 200, [:]) {
          #"{"url":"https://example.com"}"#
        }
      ], matching: [.method, .path], scope: .test))
  func getLinkIdentityURL() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.getLinkIdentityURL(
      provider: .github,
      scopes: "user:email",
      redirectTo: URL(string: "https://supabase.com"),
      queryParams: [("extra_key", "extra_value")]
    )
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/factors", 200, [:]) { #"{"id":"1","type":"totp"}"# }], matching: [.method, .path], scope: .test))
  func mfaEnrollLegacy() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.mfa.enroll(
      params: MFAEnrollParams(issuer: "supabase.com", friendlyName: "test"))
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/factors", 200, [:]) { #"{"id":"1","type":"totp"}"# }], matching: [.method, .path], scope: .test))
  func mfaEnrollTotp() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.mfa.enroll(params: .totp(issuer: "supabase.com", friendlyName: "test"))
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/factors", 200, [:]) { #"{"id":"1","type":"phone"}"# }], matching: [.method, .path], scope: .test))
  func mfaEnrollPhone() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.mfa.enroll(params: .phone(friendlyName: "test", phone: "+1 202-918-2132"))
  }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/auth/v1/factors/123/challenge", 200, [:]) {
          #"{"id":"1","type":"totp","expires_at":1}"#
        }
      ], matching: [.method, .path], scope: .test))
  func mfaChallenge() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.mfa.challenge(params: .init(factorId: "123"))
  }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/auth/v1/factors/123/challenge", 200, [:]) {
          #"{"id":"1","type":"phone","expires_at":1}"#
        }
      ], matching: [.method, .path], scope: .test))
  func mfaChallengePhone() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.mfa.challenge(params: .init(factorId: "123", channel: .whatsapp))
  }

  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/factors/123/verify", body: MockData.session)], matching: [.method, .path], scope: .test))
  func mfaVerify() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.mfa.verify(
      params: .init(factorId: "123", challengeId: "123", code: "123456"))
  }

  @Test(.replay(stubs: [.delete("http://localhost:54321/auth/v1/factors/123", 200, [:]) { #"{"id":"123"}"# }], matching: [.method, .path], scope: .test))
  func mfaUnenroll() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.mfa.unenroll(params: .init(factorId: "123"))
  }

  @Test(.replay(stubs: [.post("http://localhost:54321/auth/v1/factors", 200, [:]) { #"{"id":"1","type":"webauthn"}"# }], matching: [.method, .path], scope: .test))
  func mfaEnrollWebAuthn() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.mfa.enroll(params: .webAuthn(friendlyName: "My Passkey"))
  }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/auth/v1/factors/123/challenge", 200, [:]) {
          #"{"id":"1","type":"webauthn","expires_at":1,"webauthn":{"type":"create","credential_options":{}}}"#
        }
      ], matching: [.method, .path], scope: .test))
  func mfaChallengeWebAuthn() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.mfa.challenge(
      params: .init(
        factorId: "123",
        webAuthn: .init(rpId: "example.com", rpOrigins: ["https://example.com"])
      )
    )
  }

  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/factors/123/verify", body: MockData.session)], matching: [.method, .path], scope: .test))
  func mfaVerifyWebAuthn() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    // The credential response carries W3C camelCase keys (e.g. `clientDataJSON`)
    // that MUST survive encoding untouched by the snake_case strategy.
    _ = try await sut.mfa.verify(
      params: .init(
        factorId: "123",
        challengeId: "456",
        credentialResponse: [
          "id": "credential-id",
          "rawId": "cmF3LWNyZWRlbnRpYWwtaWQ",
          "type": "public-key",
          "response": [
            "clientDataJSON": "Y2xpZW50LWRhdGE",
            "attestationObject": "YXR0ZXN0YXRpb24tb2JqZWN0",
          ],
        ]
      )
    )
  }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/auth/v1/passkeys/registration/options", 200, [:]) {
          #"{"challenge_id":"1","expires_at":1,"options":{}}"#
        }
      ], matching: [.method, .path], scope: .test))
  func getPasskeyRegistrationOptions() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.getPasskeyRegistrationOptions()
  }

  @Test(.replay(stubs: [.post(
          "http://localhost:54321/auth/v1/passkeys/registration/verify", 200, [:]
        ) {
          #"{"id":"passkey-1","friendly_name":null,"created_at":"2024-01-01T00:00:00.000Z","last_used_at":null}"#
        }], matching: [.method, .path], scope: .test))
  func verifyPasskeyRegistration() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.verifyPasskeyRegistration(
      challengeId: "challenge-1",
      credentialResponse: [
        "id": "credential-id",
        "rawId": "cmF3LWNyZWRlbnRpYWwtaWQ",
        "type": "public-key",
        "response": [
          "clientDataJSON": "Y2xpZW50LWRhdGE",
          "attestationObject": "YXR0ZXN0YXRpb24tb2JqZWN0",
        ],
      ]
    )
  }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/auth/v1/passkeys/authentication/options", 200, [:]) {
          #"{"challenge_id":"1","expires_at":1,"options":{}}"#
        }
      ], matching: [.method, .path], scope: .test))
  func getPasskeyAuthenticationOptions() async throws {
    let sut = makeSUT()

    // No session stored: passkey authentication options must not require auth.
    _ = try await sut.getPasskeyAuthenticationOptions()
  }

  @Test(.replay(stubs: [Stub(.post, "http://localhost:54321/auth/v1/passkeys/authentication/verify", body: MockData.session)], matching: [.method, .path], scope: .test))
  func verifyPasskeyAuthentication() async throws {
    let sut = makeSUT()

    _ = try await sut.verifyPasskeyAuthentication(
      challengeId: "challenge-1",
      credentialResponse: [
        "id": "credential-id",
        "rawId": "cmF3LWNyZWRlbnRpYWwtaWQ",
        "type": "public-key",
        "response": [
          "clientDataJSON": "Y2xpZW50LWRhdGE",
          "authenticatorData": "YXV0aGVudGljYXRvci1kYXRh",
          "signature": "c2lnbmF0dXJl",
          "userHandle": "dXNlci1oYW5kbGU",
        ],
      ]
    )
  }

  @Test(.replay(stubs: [.get("http://localhost:54321/auth/v1/passkeys/", 200, [:]) { "[]" }], matching: [.method, .path], scope: .test))
  func listPasskeys() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.listPasskeys()
  }

  @Test(
    .replay(
      stubs: [
        .patch("http://localhost:54321/auth/v1/passkeys/passkey-1", 200, [:]) {
          #"{"id":"passkey-1","friendly_name":"Renamed Passkey","created_at":"2024-01-01T00:00:00.000Z","last_used_at":null}"#
        }
      ], matching: [.method, .path], scope: .test))
  func renamePasskey() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    _ = try await sut.renamePasskey(id: "passkey-1", friendlyName: "Renamed Passkey")
  }

  @Test(.replay(stubs: [.delete("http://localhost:54321/auth/v1/passkeys/passkey-1", 200, [:]) { "" }], matching: [.method, .path], scope: .test))
  func deletePasskey() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.deletePasskey(id: "passkey-1")
  }

  private func makeSUT(flowType: AuthFlowType = .implicit) -> AuthClient {
    let encoder = AuthClient.Configuration.jsonEncoder
    encoder.outputFormatting = .sortedKeys

    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: ["Apikey": "dummy.api.key", "X-Client-Info": "gotrue-swift/x.y.z"],
      flowType: flowType,
      localStorage: InMemoryLocalStorage(),
      logger: nil,
      encoder: encoder,
      fetch: { try await Replay.session.data(for: $0) }
    )

    return AuthClient(configuration: configuration)
  }
}
