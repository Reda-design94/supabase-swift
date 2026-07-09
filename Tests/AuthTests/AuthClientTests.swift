//
//  AuthClientTests.swift
//
//
//  Created by Guilherme Souza on 23/10/23.
//

import ConcurrencyExtras
import CustomDump
import Foundation
import InlineSnapshotTesting
import Replay
import TestHelpers
import Testing

@_spi(Experimental) @testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

#if canImport(AuthenticationServices)
  import AuthenticationServices
#endif

// `withMainSerialExecutor` mutates a process-global flag (ConcurrencyExtras'
// `uncheckedUseMainSerialExecutor`) to force deterministic task scheduling within its closure.
// Swift Testing runs tests in the same suite concurrently by default, so two tests racing to
// flip that global would interfere with each other — serialize this suite, mirroring the
// `_clock`-swap precedent in PostgrestBuilderTests (PR #1095).
@Suite(.serialized)
struct AuthClientTests {
  let storage = InMemoryLocalStorage()

  @Test
  func onAuthStateChanges() async {
    await withMainSerialExecutor {
      let session = Session.validSession
      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(session)

      let events = LockIsolated([AuthChangeEvent]())

      let handle = await sut.onAuthStateChange { event, _ in
        events.withValue {
          $0.append(event)
        }
      }

      expectNoDifference(events.value, [.initialSession])

      handle.remove()
    }
  }

  @Test
  func authStateChanges() async {
    await withMainSerialExecutor {
      let session = Session.validSession
      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(session)

      let stateChange = await sut.authStateChanges.first { _ in true }
      expectNoDifference(stateChange?.event, .initialSession)
      expectNoDifference(stateChange?.session, session)
    }
  }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/auth/v1/logout?scope=global", 200, [:]) { "" }
      ], scope: .test))
  func signOut() async throws {
    try await withMainSerialExecutor {
      let sut = makeSUT()

      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      try await assertAuthStateChanges(
        sut: sut,
        action: { try await sut.signOut() },
        expectedEvents: [.initialSession, .signedOut]
      )

      do {
        _ = try await sut.session
      } catch {
        assertInlineSnapshot(of: error, as: .dump) {
          """
          - AuthError.sessionMissing

          """
        }
      }
    }
  }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/auth/v1/logout?scope=others", 200, [:]) { "" }
      ], scope: .test))
  func signOutWithOthersScopeShouldNotRemoveLocalSession() async throws {
    try await withMainSerialExecutor {
      let sut = makeSUT()

      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      try await sut.signOut(scope: .others)

      let sessionRemoved = Dependencies[sut.clientID].sessionStorage.get() == nil
      #expect(!sessionRemoved)
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/logout?scope=global", status: 404, body: Data())
      ], scope: .test))
  func signOutShouldRemoveSessionIfUserIsNotFound() async throws {
    try await withMainSerialExecutor {
      let sut = makeSUT()

      let validSession = Session.validSession
      Dependencies[sut.clientID].sessionStorage.store(validSession)

      let eventsTask = Task {
        await sut.authStateChanges.prefix(2).collect()
      }

      await Task.megaYield()

      try await sut.signOut()

      let events = await eventsTask.value.map(\.event)
      let sessions = await eventsTask.value.map(\.session)

      expectNoDifference(events, [.initialSession, .signedOut])
      expectNoDifference(sessions, [.validSession, nil])

      let sessionRemoved = Dependencies[sut.clientID].sessionStorage.get() == nil
      #expect(sessionRemoved)
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/logout?scope=global", status: 401, body: Data())
      ], scope: .test))
  func signOutShouldRemoveSessionIfJWTIsInvalid() async throws {
    try await withMainSerialExecutor {
      let sut = makeSUT()

      let validSession = Session.validSession
      Dependencies[sut.clientID].sessionStorage.store(validSession)

      let eventsTask = Task {
        await sut.authStateChanges.prefix(2).collect()
      }

      await Task.megaYield()

      try await sut.signOut()

      let events = await eventsTask.value.map(\.event)
      let sessions = await eventsTask.value.map(\.session)

      expectNoDifference(events, [.initialSession, .signedOut])
      expectNoDifference(sessions, [validSession, nil])

      let sessionRemoved = Dependencies[sut.clientID].sessionStorage.get() == nil
      #expect(sessionRemoved)
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/logout?scope=global", status: 403, body: Data())
      ], scope: .test))
  func signOutShouldRemoveSessionIf403Returned() async throws {
    try await withMainSerialExecutor {
      let sut = makeSUT()

      let validSession = Session.validSession
      Dependencies[sut.clientID].sessionStorage.store(validSession)

      let eventsTask = Task {
        await sut.authStateChanges.prefix(2).collect()
      }

      await Task.megaYield()

      try await sut.signOut()

      let events = await eventsTask.value.map(\.event)
      let sessions = await eventsTask.value.map(\.session)

      expectNoDifference(events, [.initialSession, .signedOut])
      expectNoDifference(sessions, [validSession, nil])

      let sessionRemoved = Dependencies[sut.clientID].sessionStorage.get() == nil
      #expect(sessionRemoved)
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/signup", body: MockData.anonymousSignInResponse)
      ],
      matching: [.method, .path, .query, matchingBody("{}")],
      scope: .test))
  func signInAnonymously() async throws {
    try await withMainSerialExecutor {
      let session = Session(fromMockNamed: "anonymous-sign-in-response")

      let sut = makeSUT()

      _ = try await assertAuthStateChanges(
        sut: sut,
        action: { try await sut.signInAnonymously() },
        expectedEvents: [.initialSession, .signedIn],
        expectedSessions: [nil, session]
      )

      expectNoDifference(sut.currentSession, session)
      expectNoDifference(sut.currentUser, session.user)
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/token?grant_type=pkce", body: MockData.session)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"auth_code":"12345","code_verifier":"nt_xCJhJXUsIlTmbE_b0r3VHDKLxFTAwXYSj1xF3ZPaulO2gejNornLLiW_C3Ru4w-5lqIh1XE2LTOsSKrj7iA"}"#
        ),
      ],
      scope: .test))
  func signInWithOAuth() async throws {
    try await withMainSerialExecutor {
      let sut = makeSUT()

      let eventsTask = Task {
        await sut.authStateChanges.prefix(2).collect()
      }

      await Task.megaYield()

      try await sut.signInWithOAuth(
        provider: .google,
        redirectTo: URL(string: "supabase://auth-callback")
      ) { (url: URL) in
        URL(string: "supabase://auth-callback?code=12345") ?? url
      }

      let events = await eventsTask.value.map(\.event)

      expectNoDifference(events, [.initialSession, .signedIn])
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get,
          "http://localhost:54321/auth/v1/user/identities/authorize?code_challenge=hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY&code_challenge_method=s256&provider=github&skip_http_redirect=true",
          body: Data(
            """
            {
              "url": "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt"
            }
            """.utf8))
      ], matching: [.method, .path, .query], scope: .test))
  func getLinkIdentityURL() async throws {
    try await withMainSerialExecutor {
      let url =
        "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt"
      let sut = makeSUT()

      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      let response = try await sut.getLinkIdentityURL(provider: .github)

      expectNoDifference(
        response,
        OAuthResponse(
          provider: .github,
          url: URL(
            string: url
          )!
        )
      )
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get,
          "http://localhost:54321/auth/v1/user/identities/authorize?code_challenge=hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY&code_challenge_method=s256&provider=github&skip_http_redirect=true",
          body: Data(
            """
            {
              "url": "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt"
            }
            """.utf8))
      ], matching: [.method, .path, .query], scope: .test))
  func linkIdentity() async throws {
    try await withMainSerialExecutor {
      let url =
        "https://github.com/login/oauth/authorize?client_id=1234&redirect_to=com.supabase.swift-examples://&redirect_uri=http://127.0.0.1:54321/auth/v1/callback&response_type=code&scope=user:email&skip_http_redirect=true&state=jwt"

      let sut = makeSUT()

      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      let receivedURL = LockIsolated<URL?>(nil)
      Dependencies[sut.clientID].urlOpener.open = { url in
        receivedURL.setValue(url)
      }

      try await sut.linkIdentity(provider: .github)

      expectNoDifference(receivedURL.value?.absoluteString, url)
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/token?grant_type=id_token", body: MockData.session)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"access_token":"access-token","gotrue_meta_security":{"captcha_token":"captcha-token"},"id_token":"id-token","link_identity":true,"nonce":"nonce","provider":"apple"}"#
        ),
      ],
      scope: .test))
  func linkIdentityWithIdToken() async throws {
    try await withMainSerialExecutor {
      let sut = makeSUT()

      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      let updatedSession = try await assertAuthStateChanges(
        sut: sut,
        action: {
          try await sut.linkIdentityWithIdToken(
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
        },
        expectedEvents: [.initialSession, .userUpdated]
      )

      expectNoDifference(sut.currentSession, updatedSession)
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/admin/users?page=&per_page=",
          headers: [
            "X-Total-Count": "669",
            "Link":
              "</admin/users?page=2&per_page=>; rel=\"next\", </admin/users?page=14&per_page=>; rel=\"last\"",
          ],
          body: MockData.listUsersResponse)
      ], scope: .test))
  func adminListUsers() async throws {
    let sut = makeSUT()

    let response = try await sut.admin.listUsers()
    expectNoDifference(response.total, 669)
    expectNoDifference(response.nextPage, 2)
    expectNoDifference(response.lastPage, 14)
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/admin/users?page=&per_page=",
          headers: [
            "X-Total-Count": "669",
            "Link": "</admin/users?page=14&per_page=>; rel=\"last\"",
          ],
          body: MockData.listUsersResponse)
      ], scope: .test))
  func adminListUsers_noNextPage() async throws {
    let sut = makeSUT()

    let response = try await sut.admin.listUsers()
    expectNoDifference(response.total, 669)
    #expect(response.nextPage == nil)
    expectNoDifference(response.lastPage, 14)
  }

  @Test
  func sessionFromURL_withError() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].codeVerifierStorage.set("code-verifier")

    let url = URL(
      string:
        "https://my.redirect.com?error=server_error&error_code=422&error_description=Identity+is+already+linked+to+another+user#error=server_error&error_code=422&error_description=Identity+is+already+linked+to+another+user"
    )!

    do {
      try await sut.session(from: url)
      Issue.record("Expect failure")
    } catch {
      expectNoDifference(
        error as? AuthError,
        AuthError.pkceGrantCodeExchange(
          message: "Identity is already linked to another user",
          error: "server_error",
          code: "422"
        )
      )
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/signup?redirect_to=https://supabase.com",
          body: MockData.session)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"code_challenge":"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY","code_challenge_method":"s256","data":{"custom_key":"custom_value"},"email":"example@mail.com","gotrue_meta_security":{"captcha_token":"dummy-captcha"},"password":"the.pass"}"#
        ),
      ],
      scope: .test))
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

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/signup", body: MockData.session)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"channel":"sms","data":{"custom_key":"custom_value"},"gotrue_meta_security":{"captcha_token":"dummy-captcha"},"password":"the.pass","phone":"+1 202-918-2132"}"#
        ),
      ],
      scope: .test))
  func signUpWithPhoneAndPassword() async throws {
    let sut = makeSUT()

    try await sut.signUp(
      phone: "+1 202-918-2132",
      password: "the.pass",
      data: ["custom_key": .string("custom_value")],
      captchaToken: "dummy-captcha"
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/token?grant_type=password", body: MockData.session)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"email":"example@mail.com","gotrue_meta_security":{"captcha_token":"dummy-captcha"},"password":"the.pass"}"#
        ),
      ],
      scope: .test))
  func signInWithEmailAndPassword() async throws {
    let sut = makeSUT()

    try await sut.signIn(
      email: "example@mail.com",
      password: "the.pass",
      captchaToken: "dummy-captcha"
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/token?grant_type=password", body: MockData.session)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"gotrue_meta_security":{"captcha_token":"dummy-captcha"},"password":"the.pass","phone":"+1 202-918-2132"}"#
        ),
      ],
      scope: .test))
  func signInWithPhoneAndPassword() async throws {
    let sut = makeSUT()

    try await sut.signIn(
      phone: "+1 202-918-2132",
      password: "the.pass",
      captchaToken: "dummy-captcha"
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/token?grant_type=id_token", body: MockData.session)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"access_token":"access-token","gotrue_meta_security":{"captcha_token":"captcha-token"},"id_token":"id-token","link_identity":false,"nonce":"nonce","provider":"apple"}"#
        ),
      ],
      scope: .test))
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

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/otp?redirect_to=https://supabase.com", body: Data())
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"code_challenge":"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY","code_challenge_method":"s256","create_user":true,"data":{"custom_key":"custom_value"},"email":"example@mail.com","gotrue_meta_security":{"captcha_token":"dummy-captcha"}}"#
        ),
      ],
      scope: .test))
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

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/otp", body: Data())
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"channel":"sms","create_user":true,"data":{"custom_key":"custom_value"},"gotrue_meta_security":{"captcha_token":"dummy-captcha"},"phone":"+1 202-918-2132"}"#
        ),
      ],
      scope: .test))
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
    let sut = makeSUT(flowType: .implicit)
    let url = try sut.getOAuthSignInURL(
      provider: .github,
      scopes: "read,write",
      redirectTo: URL(string: "https://dummy-url.com/redirect")!,
      queryParams: [("extra_key", "extra_value")]
    )
    expectNoDifference(
      url,
      URL(
        string:
          "http://localhost:54321/auth/v1/authorize?provider=github&scopes=read,write&redirect_to=https://dummy-url.com/redirect&extra_key=extra_value"
      )!
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/token?grant_type=refresh_token",
          body: MockData.session)
      ],
      matching: [.method, .path, .query, matchingBody(#"{"refresh_token":"refresh-token"}"#)],
      scope: .test))
  func refreshSession() async throws {
    let sut = makeSUT()
    try await sut.refreshSession(refreshToken: "refresh-token")
  }

  #if !os(Linux) && !os(Windows) && !os(Android)
    @Test(
      .replay(
        stubs: [
          Stub(.get, "http://localhost:54321/auth/v1/user", body: MockData.user)
        ], scope: .test))
    func sessionFromURL() async throws {
      let sut = makeSUT(flowType: .implicit)

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
      expectNoDifference(session, expectedSession)
    }
  #endif

  @Test(
    .replay(
      stubs: [
        Stub(.get, "http://localhost:54321/auth/v1/user", body: MockData.user)
      ], scope: .test))
  func sessionWithURL_implicitFlow() async throws {
    let sut = makeSUT(flowType: .implicit)

    let url = URL(
      string:
        "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
    )!
    try await sut.session(from: url)
  }

  @Test
  func sessionWithURL_implicitFlow_invalidURL() async throws {
    let sut = makeSUT(flowType: .implicit)

    let url = URL(
      string:
        "https://dummy-url.com/callback#invalid_key=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer"
    )!

    do {
      try await sut.session(from: url)
    } catch let AuthError.implicitGrantRedirect(message) {
      expectNoDifference(message, "Not a valid implicit grant flow URL: \(url)")
    }
  }

  @Test
  func sessionWithURL_implicitFlow_error() async throws {
    let sut = makeSUT(flowType: .implicit)

    let url = URL(
      string:
        "https://dummy-url.com/callback#error_description=Invalid+code&error=invalid_grant"
    )!

    do {
      try await sut.session(from: url)
    } catch let AuthError.implicitGrantRedirect(message) {
      expectNoDifference(message, "Invalid code")
    }
  }

  @Test
  func sessionWithURL_implicitFlow_errorQueryParam() async throws {
    let sut = makeSUT(flowType: .implicit)

    let url = URL(
      string:
        "https://dummy-url.com/callback?error=access_denied&error_description=User+denied+access"
    )!

    do {
      try await sut.session(from: url)
      Issue.record("Expected implicitGrantRedirect error")
    } catch let AuthError.implicitGrantRedirect(message) {
      expectNoDifference(message, "User denied access")
    }
  }

  @Test
  func sessionWithURL_implicitFlow_errorQueryParamNoDescription() async throws {
    let sut = makeSUT(flowType: .implicit)

    let url = URL(string: "https://dummy-url.com/callback?error=access_denied")!

    do {
      try await sut.session(from: url)
      Issue.record("Expected implicitGrantRedirect error")
    } catch let AuthError.implicitGrantRedirect(message) {
      expectNoDifference(message, "access_denied")
    }
  }

  @Test
  func sessionWithURL_implicitFlow_errorHashFragmentNoDescription() async throws {
    let sut = makeSUT(flowType: .implicit)

    let url = URL(string: "https://dummy-url.com/callback#error=access_denied")!

    do {
      try await sut.session(from: url)
      Issue.record("Expected implicitGrantRedirect error")
    } catch let AuthError.implicitGrantRedirect(message) {
      expectNoDifference(message, "access_denied")
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(.get, "http://localhost:54321/auth/v1/user", body: MockData.user)
      ], scope: .test))
  func sessionWithURL_implicitFlow_recoveryType() async throws {
    let sut = makeSUT(flowType: .implicit)

    let url = URL(
      string:
        "https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken&token_type=bearer&type=recovery"
    )!

    let eventsTask = Task {
      await sut.authStateChanges.prefix(3).collect().map(\.event)
    }

    await Task.yield()

    try await sut.session(from: url)

    let events = await eventsTask.value
    expectNoDifference(events, [.initialSession, .signedIn, .passwordRecovery])
  }

  @Test
  func sessionWithURL_pkceFlow_error() async throws {
    let sut = makeSUT()

    let url = URL(
      string:
        "https://dummy-url.com/callback#error_description=Invalid+code&error=invalid_grant&error_code=500"
    )!

    do {
      try await sut.session(from: url)
    } catch let AuthError.pkceGrantCodeExchange(message, error, code) {
      expectNoDifference(message, "Invalid code")
      expectNoDifference(error, "invalid_grant")
      expectNoDifference(code, "500")
    }
  }

  @Test
  func sessionWithURL_pkceFlow_error_noErrorDescription() async throws {
    let sut = makeSUT()

    let url = URL(
      string:
        "https://dummy-url.com/callback#error=invalid_grant&error_code=500"
    )!

    do {
      try await sut.session(from: url)
    } catch let AuthError.pkceGrantCodeExchange(message, error, code) {
      expectNoDifference(message, "Error in URL with unspecified error_description.")
      expectNoDifference(error, "invalid_grant")
      expectNoDifference(code, "500")
    }
  }

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
          ▿ pkceGrantCodeExchange: (3 elements)
            - message: "Not a valid PKCE flow URL: https://dummy-url.com/callback#access_token=accesstoken&expires_in=60&refresh_token=refreshtoken"
            - error: Optional<String>.none
            - code: Optional<String>.none

        """
      }
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(.get, "http://localhost:54321/auth/v1/user", body: MockData.user)
      ], scope: .test))
  func setSessionWithAFutureExpirationDate() async throws {
    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo0ODUyMTYzNTkzLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.UiEhoahP9GNrBKw_OHBWyqYudtoIlZGkrjs7Qa8hU7I"

    try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/token?grant_type=refresh_token",
          body: MockData.session)
      ],
      matching: [.method, .path, .query, matchingBody(#"{"refresh_token":"dummy-refresh-token"}"#)],
      scope: .test))
  func setSessionWithAExpiredToken() async throws {
    let sut = makeSUT()

    let accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjoxNjQ4NjQwMDIxLCJzdWIiOiJmMzNkM2VjOS1hMmVlLTQ3YzQtODBlMS01YmQ5MTlmM2Q4YjgiLCJlbWFpbCI6ImhpQGJpbmFyeXNjcmFwaW5nLmNvIiwicGhvbmUiOiIiLCJhcHBfbWV0YWRhdGEiOnsicHJvdmlkZXIiOiJlbWFpbCIsInByb3ZpZGVycyI6WyJlbWFpbCJdfSwidXNlcl9tZXRhZGF0YSI6e30sInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.CGr5zNE5Yltlbn_3Ms2cjSLs_AW9RKM3lxh7cTQrg0w"

    try await sut.setSession(accessToken: accessToken, refreshToken: "dummy-refresh-token")
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/verify?redirect_to=https://supabase.com",
          body: MockData.session)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"email":"example@mail.com","gotrue_meta_security":{"captcha_token":"captcha-token"},"token":"123456","type":"magiclink"}"#
        ),
      ],
      scope: .test))
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

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/verify", body: MockData.session)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"gotrue_meta_security":{"captcha_token":"captcha-token"},"phone":"+1 202-918-2132","token":"123456","type":"sms"}"#
        ),
      ],
      scope: .test))
  func verifyOTPUsingPhone() async throws {
    let sut = makeSUT()

    try await sut.verifyOTP(
      phone: "+1 202-918-2132",
      token: "123456",
      type: .sms,
      captchaToken: "captcha-token"
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/verify", body: MockData.session)
      ],
      matching: [.method, .path, .query, matchingBody(#"{"token_hash":"abc-def","type":"email"}"#)],
      scope: .test))
  func verifyOTPUsingTokenHash() async throws {
    let sut = makeSUT()

    try await sut.verifyOTP(
      tokenHash: "abc-def",
      type: .email
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(.put, "http://localhost:54321/auth/v1/user", body: MockData.user)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"code_challenge":"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY","code_challenge_method":"s256","data":{"custom_key":"custom_value"},"email":"example@mail.com","email_change_token":"123456","nonce":"abcdef","password":"another.pass","phone":"+1 202-918-2132"}"#
        ),
      ],
      scope: .test))
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

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/recover?redirect_to=https://supabase.com", body: Data())
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"code_challenge":"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY","code_challenge_method":"s256","email":"example@mail.com","gotrue_meta_security":{"captcha_token":"captcha-token"}}"#
        ),
      ],
      scope: .test))
  func resetPasswordForEmail() async throws {
    let sut = makeSUT()
    try await sut.resetPasswordForEmail(
      "example@mail.com",
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/resend?redirect_to=https://supabase.com", body: Data())
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"code_challenge":"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY","code_challenge_method":"s256","email":"example@mail.com","gotrue_meta_security":{"captcha_token":"captcha-token"},"type":"email_change"}"#
        ),
      ],
      scope: .test))
  func resendEmail() async throws {
    let sut = makeSUT()

    try await sut.resend(
      email: "example@mail.com",
      type: .emailChange,
      emailRedirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/resend?redirect_to=https://supabase.com", body: Data())
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"email":"example@mail.com","gotrue_meta_security":{"captcha_token":"captcha-token"},"type":"email_change"}"#
        ),
      ],
      scope: .test))
  func resendEmailImplicitFlow() async throws {
    let sut = makeSUT(flowType: .implicit)

    try await sut.resend(
      email: "example@mail.com",
      type: .emailChange,
      emailRedirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/resend", body: Data(#"{"message_id": "12345"}"#.utf8))
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"gotrue_meta_security":{"captcha_token":"captcha-token"},"phone":"+1 202-918-2132","type":"phone_change"}"#
        ),
      ],
      scope: .test))
  func resendPhone() async throws {
    let sut = makeSUT()

    let response = try await sut.resend(
      phone: "+1 202-918-2132",
      type: .phoneChange,
      captchaToken: "captcha-token"
    )

    expectNoDifference(response.messageId, "12345")
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .delete, "http://localhost:54321/auth/v1/admin/users/E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          status: 204, body: Data())
      ],
      matching: [.method, .path, .query, matchingBody(#"{"should_soft_delete":false}"#)],
      scope: .test))
  func deleteUser() async throws {
    let id = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

    let sut = makeSUT()
    try await sut.admin.deleteUser(id: id)
  }

  @Test(
    .replay(
      stubs: [
        Stub(.get, "http://localhost:54321/auth/v1/reauthenticate", body: Data())
      ], scope: .test))
  func reauthenticate() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.reauthenticate()
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .delete, "http://localhost:54321/auth/v1/user/identities/E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          status: 204, body: Data())
      ], scope: .test))
  func unlinkIdentity() async throws {
    let identityId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.unlinkIdentity(
      UserIdentity(
        id: "5923044",
        identityId: identityId,
        userId: UUID(),
        identityData: [:],
        provider: "email",
        createdAt: Date(),
        lastSignInAt: Date(),
        updatedAt: Date()
      )
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/sso", body: Data(#"{"url":"https://supabase.com"}"#.utf8))
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"code_challenge":"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY","code_challenge_method":"s256","domain":"supabase.com","gotrue_meta_security":{"captcha_token":"captcha-token"},"redirect_to":"https://supabase.com"}"#
        ),
      ],
      scope: .test))
  func signInWithSSOUsingDomain() async throws {
    let sut = makeSUT()

    let response = try await sut.signInWithSSO(
      domain: "supabase.com",
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )

    expectNoDifference(response.url, URL(string: "https://supabase.com")!)
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/sso", body: Data(#"{"url":"https://supabase.com"}"#.utf8))
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"code_challenge":"hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY","code_challenge_method":"s256","gotrue_meta_security":{"captcha_token":"captcha-token"},"provider_id":"E621E1F8-C36C-495A-93FC-0C247A3E6E5F","redirect_to":"https://supabase.com"}"#
        ),
      ],
      scope: .test))
  func signInWithSSOUsingProviderId() async throws {
    let sut = makeSUT()

    let response = try await sut.signInWithSSO(
      providerId: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
      redirectTo: URL(string: "https://supabase.com"),
      captchaToken: "captcha-token"
    )

    expectNoDifference(response.url, URL(string: "https://supabase.com")!)
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/factors",
          body: Data(
            """
            {
              "id": "12345",
              "type": "totp"
            }
            """.utf8))
      ],
      matching: [
        .method, .path, .query,
        matchingBody(#"{"factor_type":"totp","friendly_name":"test","issuer":"supabase.com"}"#),
      ],
      scope: .test))
  func mfaEnrollLegacy() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.mfa.enroll(
      params: MFAEnrollParams(
        issuer: "supabase.com",
        friendlyName: "test"
      )
    )

    expectNoDifference(response.id, "12345")
    expectNoDifference(response.type, "totp")
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/factors",
          body: Data(
            """
            {
              "id": "12345",
              "type": "totp"
            }
            """.utf8))
      ],
      matching: [
        .method, .path, .query,
        matchingBody(#"{"factor_type":"totp","friendly_name":"test","issuer":"supabase.com"}"#),
      ],
      scope: .test))
  func mfaEnrollTotp() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.mfa.enroll(
      params: .totp(
        issuer: "supabase.com",
        friendlyName: "test"
      )
    )

    expectNoDifference(response.id, "12345")
    expectNoDifference(response.type, "totp")
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/factors",
          body: Data(
            """
            {
              "id": "12345",
              "type": "phone"
            }
            """.utf8))
      ],
      matching: [
        .method, .path, .query,
        matchingBody(#"{"factor_type":"phone","friendly_name":"test","phone":"+1 202-918-2132"}"#),
      ],
      scope: .test))
  func mfaEnrollPhone() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.mfa.enroll(
      params: .phone(
        friendlyName: "test",
        phone: "+1 202-918-2132"
      )
    )

    expectNoDifference(response.id, "12345")
    expectNoDifference(response.type, "phone")
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/factors/123/challenge",
          body: Data(
            """
            {
              "id": "12345",
              "type": "totp",
              "expires_at": 12345678
            }
            """.utf8))
      ], matching: [.method, .path, .query], scope: .test))
  func mfaChallenge() async throws {
    let factorId = "123"

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.mfa.challenge(params: .init(factorId: factorId))

    expectNoDifference(
      response,
      AuthMFAChallengeResponse(
        id: "12345",
        type: "totp",
        expiresAt: 12_345_678
      )
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/factors/123/challenge",
          body: Data(
            """
            {
              "id": "12345",
              "type": "phone",
              "expires_at": 12345678
            }
            """.utf8))
      ],
      matching: [.method, .path, .query, matchingBody(#"{"channel":"sms"}"#)],
      scope: .test))
  func mfaChallengeWithPhoneType() async throws {
    let factorId = "123"

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.mfa.challenge(
      params: .init(
        factorId: factorId,
        channel: .sms
      )
    )

    expectNoDifference(
      response,
      AuthMFAChallengeResponse(
        id: "12345",
        type: "phone",
        expiresAt: 12_345_678
      )
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/factors/123/challenge",
          body: Data(
            """
            {
              "id": "challenge-1",
              "type": "webauthn",
              "expires_at": 12345678,
              "webauthn": {
                "type": "create",
                "credential_options": {
                  "challenge": "Y2hhbGxlbmdl",
                  "rp": { "id": "example.com", "name": "Example" },
                  "pubKeyCredParams": [{ "alg": -7, "type": "public-key" }]
                }
              }
            }
            """.utf8))
      ], matching: [.method, .path, .query], scope: .test))
  func mfaChallengeWebAuthnReturnsCredentialOptions() async throws {
    let factorId = "123"

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let response = try await sut.mfa.challenge(
      params: .init(factorId: factorId, webAuthn: .init(rpId: "example.com"))
    )

    expectNoDifference(response.id, "challenge-1")
    expectNoDifference(response.type, "webauthn")
    expectNoDifference(response.webauthn?.type, .create)

    // W3C option keys are camelCase and must survive decoding untouched.
    let options = response.webauthn?.credentialOptions.objectValue
    expectNoDifference(options?["challenge"]?.stringValue, "Y2hhbGxlbmdl")
    expectNoDifference(options?["pubKeyCredParams"]?.arrayValue?.count, 1)
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/factors/123/verify", body: MockData.session)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(#"{"challenge_id":"123","code":"123456","factor_id":"123"}"#),
      ],
      scope: .test))
  func mfaVerify() async throws {
    let factorId = "123"

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.mfa.verify(
      params: .init(
        factorId: factorId,
        challengeId: "123",
        code: "123456"
      )
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .delete, "http://localhost:54321/auth/v1/factors/123", body: Data(#"{"id":"123"}"#.utf8))
      ], scope: .test))
  func mfaUnenroll() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let id = try await sut.mfa.unenroll(params: .init(factorId: "123")).id

    expectNoDifference(id, "123")
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/factors/123/challenge",
          body: Data(
            """
            {
              "id": "12345",
              "type": "totp",
              "expires_at": 12345678
            }
            """.utf8)),
        Stub(.post, "http://localhost:54321/auth/v1/factors/123/verify", body: MockData.session),
      ],
      matching: [.method, .path, .query],
      scope: .test))
  func mfaChallengeAndVerify() async throws {
    let factorId = "123"
    let code = "456"

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await sut.mfa.challengeAndVerify(
      params: MFAChallengeAndVerifyParams(
        factorId: factorId,
        code: code
      )
    )
  }

  @Test
  func mfaListFactors() async throws {
    let sut = makeSUT()

    var session = Session.validSession
    session.user.factors = [
      Factor(
        id: "1",
        friendlyName: nil,
        factorType: "totp",
        status: .verified,
        createdAt: Date(),
        updatedAt: Date()
      ),
      Factor(
        id: "2",
        friendlyName: nil,
        factorType: "totp",
        status: .unverified,
        createdAt: Date(),
        updatedAt: Date()
      ),
      Factor(
        id: "3",
        friendlyName: nil,
        factorType: "phone",
        status: .verified,
        createdAt: Date(),
        updatedAt: Date()
      ),
      Factor(
        id: "4",
        friendlyName: nil,
        factorType: "phone",
        status: .unverified,
        createdAt: Date(),
        updatedAt: Date()
      ),
    ]

    Dependencies[sut.clientID].sessionStorage.store(session)

    let factors = try await sut.mfa.listFactors()
    expectNoDifference(factors.totp.map(\.id), ["1"])
    expectNoDifference(factors.phone.map(\.id), ["3"])
  }

  @Test
  func mfaListFactorsIncludesWebAuthn() async throws {
    let sut = makeSUT()

    var session = Session.validSession
    session.user.factors = [
      Factor(
        id: "1",
        friendlyName: "My Passkey",
        factorType: "webauthn",
        status: .verified,
        createdAt: Date(),
        updatedAt: Date()
      ),
      Factor(
        id: "2",
        friendlyName: nil,
        factorType: "webauthn",
        status: .unverified,
        createdAt: Date(),
        updatedAt: Date()
      ),
      Factor(
        id: "3",
        friendlyName: nil,
        factorType: "totp",
        status: .verified,
        createdAt: Date(),
        updatedAt: Date()
      ),
    ]

    Dependencies[sut.clientID].sessionStorage.store(session)

    let factors = try await sut.mfa.listFactors()
    expectNoDifference(factors.webauthn.map(\.id), ["1"])
    expectNoDifference(factors.totp.map(\.id), ["3"])
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/passkeys/registration/options",
          body: Data(
            """
            {
              "challenge_id": "challenge-1",
              "expires_at": 1705312800,
              "options": {
                "challenge": "Y2hhbGxlbmdl",
                "rp": { "id": "example.com", "name": "Example" },
                "user": { "id": "dXNlci1pZA", "name": "user@example.com", "displayName": "User" },
                "pubKeyCredParams": [{ "alg": -7, "type": "public-key" }]
              }
            }
            """.utf8))
      ], matching: [.method, .path, .query], scope: .test))
  func getPasskeyRegistrationOptionsDecodesOptions() async throws {
    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let options = try await sut.getPasskeyRegistrationOptions()

    expectNoDifference(options.challengeId, "challenge-1")
    expectNoDifference(options.options.objectValue?["challenge"]?.stringValue, "Y2hhbGxlbmdl")
    // W3C option keys (camelCase) must survive decoding untouched.
    expectNoDifference(options.options.objectValue?["pubKeyCredParams"]?.arrayValue?.count, 1)
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/passkeys/",
          body: Data(
            """
            [
              {
                "id": "p1",
                "friendly_name": "Work Laptop",
                "created_at": "2024-01-15T10:00:00.000Z",
                "last_used_at": "2024-02-01T08:30:00.000Z"
              },
              {
                "id": "p2",
                "friendly_name": null,
                "created_at": "2024-01-16T10:00:00.000Z",
                "last_used_at": null
              }
            ]
            """.utf8))
      ], matching: [.method, .path, .query], scope: .test))
  func listPasskeysReturnsItems() async throws {
    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    let passkeys = try await sut.listPasskeys()

    expectNoDifference(passkeys.map(\.id), ["p1", "p2"])
    expectNoDifference(passkeys[0].friendlyName, "Work Laptop")
    expectNoDifference(passkeys[1].friendlyName, nil)
    expectNoDifference(passkeys[1].lastUsedAt, nil)
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/passkeys/authentication/verify",
          body: MockData.session)
      ], scope: .test))
  func verifyPasskeyAuthenticationUpdatesSession() async throws {
    let sut = makeSUT()

    let response = try await sut.verifyPasskeyAuthentication(
      challengeId: "challenge-1",
      credentialResponse: [
        "id": "credential-id",
        "rawId": "cmF3LWlk",
        "type": "public-key",
        "response": [
          "clientDataJSON": "Y2xpZW50LWRhdGE",
          "authenticatorData": "YXV0aA",
          "signature": "c2ln",
        ],
      ]
    )

    #expect(response.session != nil)

    // The returned session is persisted by the SDK (read storage directly to avoid a refresh).
    let stored = Dependencies[sut.clientID].sessionStorage.get()
    expectNoDifference(stored?.accessToken, response.session?.accessToken)
  }

  @Test
  func webAuthnCredentialOptionsParsing() throws {
    let options: AnyJSON = [
      "challenge": "Y2hhbGxlbmdl",
      "user": [
        "id": "dXNlci1pZA",
        "name": "user@example.com",
        "displayName": "User",
      ],
    ]

    expectNoDifference(
      String(data: try options.webAuthnChallengeData(), encoding: .utf8),
      "challenge"
    )
    expectNoDifference(
      String(data: try options.webAuthnUserID(), encoding: .utf8),
      "user-id"
    )
    expectNoDifference(try options.webAuthnUserName(), "user@example.com")
  }

  @Test
  func webAuthnChallengeParsingThrowsWhenMissing() {
    let options: AnyJSON = ["user": ["id": "dXNlci1pZA"]]
    #expect(throws: (any Error).self) { try options.webAuthnChallengeData() }
  }

  #if canImport(AuthenticationServices) && !os(tvOS) && !os(watchOS)
    @Test(
      .replay(
        stubs: [
          Stub(
            .post, "http://localhost:54321/auth/v1/passkeys/authentication/options",
            body: Data(
              #"{"challenge_id":"ch-1","expires_at":1705312800,"options":{"challenge":"Y2hhbGxlbmdl","rpId":"example.com"}}"#
                .utf8)),
          Stub(
            .post, "http://localhost:54321/auth/v1/passkeys/authentication/verify",
            body: MockData.session),
        ],
        matching: [.method, .path, .query],
        scope: .test))
    @MainActor
    func signInWithPasskeyDrivesFullFlow() async throws {
      // Capture what the SDK hands to the authenticator to prove it forwards the backend options.
      let forwardedOptions = LockIsolated<AnyJSON?>(nil)
      let authenticator = WebAuthnAuthenticator(
        register: { _, _, _ in [:] },
        authenticate: { options, _, _ in
          forwardedOptions.setValue(options)
          return [
            "id": "cred", "rawId": "cmF3", "type": "public-key",
            "response": [
              "clientDataJSON": "Y2Rh", "authenticatorData": "YXV0aA", "signature": "c2ln",
            ],
          ]
        }
      )

      let sut = makeSUT()

      let response = try await sut._signInWithPasskey(
        presentationAnchor: ASPresentationAnchor(),
        authenticator: authenticator
      )

      #expect(response.session != nil)
      expectNoDifference(
        forwardedOptions.value?.objectValue?["challenge"]?.stringValue, "Y2hhbGxlbmdl")
    }

    @Test(
      .replay(
        stubs: [
          Stub(
            .post, "http://localhost:54321/auth/v1/passkeys/registration/options",
            body: Data(
              #"{"challenge_id":"ch-1","expires_at":1705312800,"options":{"challenge":"Y2hhbGxlbmdl","rp":{"id":"example.com"},"user":{"id":"dXNlci1pZA","name":"u@e.com"}}}"#
                .utf8)),
          Stub(
            .post, "http://localhost:54321/auth/v1/passkeys/registration/verify",
            body: Data(
              #"{"id":"p1","friendly_name":"My Passkey","created_at":"2024-01-15T10:00:00.000Z","last_used_at":null}"#
                .utf8)),
        ],
        matching: [.method, .path, .query],
        scope: .test))
    @MainActor
    func registerPasskeyDrivesFullFlow() async throws {
      let authenticator = WebAuthnAuthenticator(
        register: { _, _, _ in
          [
            "id": "cred", "rawId": "cmF3", "type": "public-key",
            "response": ["clientDataJSON": "Y2Rh", "attestationObject": "YXR0"],
          ]
        },
        authenticate: { _, _, _ in [:] }
      )

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      let passkey = try await sut._registerPasskey(
        presentationAnchor: ASPresentationAnchor(),
        authenticator: authenticator
      )

      expectNoDifference(passkey.id, "p1")
      expectNoDifference(passkey.friendlyName, "My Passkey")
    }

    @Test(
      .replay(
        stubs: [
          Stub(
            .post, "http://localhost:54321/auth/v1/factors",
            body: Data(#"{"id":"factor-1","type":"webauthn"}"#.utf8)),
          Stub(
            .post, "http://localhost:54321/auth/v1/factors/factor-1/challenge",
            body: Data(
              #"{"id":"ch-1","type":"webauthn","expires_at":12345678,"webauthn":{"type":"create","credential_options":{"challenge":"Y2hhbGxlbmdl","rp":{"id":"example.com"}}}}"#
                .utf8)),
          Stub(
            .post, "http://localhost:54321/auth/v1/factors/factor-1/verify", body: MockData.session),
        ],
        matching: [.method, .path, .query],
        scope: .test))
    @MainActor
    func enrollWebAuthnFactorDrivesFullFlow() async throws {
      let authenticator = WebAuthnAuthenticator(
        register: { _, _, _ in
          [
            "id": "cred", "rawId": "cmF3", "type": "public-key",
            "response": ["clientDataJSON": "Y2Rh", "attestationObject": "YXR0"],
          ]
        },
        authenticate: { _, _, _ in [:] }
      )

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      let session = try await sut.mfa._enrollWebAuthnFactor(
        friendlyName: "My Passkey",
        presentationAnchor: ASPresentationAnchor(),
        authenticator: authenticator
      )

      #expect(!session.accessToken.isEmpty)
    }

    @Test(
      .replay(
        stubs: [
          Stub(
            .post, "http://localhost:54321/auth/v1/factors/factor-1/challenge",
            body: Data(
              #"{"id":"ch-1","type":"webauthn","expires_at":12345678,"webauthn":{"type":"request","credential_options":{"challenge":"Y2hhbGxlbmdl","rpId":"example.com"}}}"#
                .utf8)),
          Stub(
            .post, "http://localhost:54321/auth/v1/factors/factor-1/verify", body: MockData.session),
        ],
        matching: [.method, .path, .query],
        scope: .test))
    @MainActor
    func verifyWebAuthnFactorDrivesFullFlow() async throws {
      let forwardedRpId = LockIsolated<String?>(nil)
      let authenticator = WebAuthnAuthenticator(
        register: { _, _, _ in [:] },
        authenticate: { _, rpId, _ in
          forwardedRpId.setValue(rpId)
          return [
            "id": "cred", "rawId": "cmF3", "type": "public-key",
            "response": [
              "clientDataJSON": "Y2Rh", "authenticatorData": "YXV0aA", "signature": "c2ln",
            ],
          ]
        }
      )

      let sut = makeSUT()
      Dependencies[sut.clientID].sessionStorage.store(.validSession)

      let session = try await sut.mfa._verifyWebAuthnFactor(
        factorId: "factor-1",
        presentationAnchor: ASPresentationAnchor(),
        authenticator: authenticator
      )

      #expect(!session.accessToken.isEmpty)
      // rpId is extracted from the server-returned credential_options, not passed by the caller.
      expectNoDifference(forwardedRpId.value, "example.com")
    }
  #endif

  @Test
  func getAuthenticatorAssuranceLevel_whenAALAndVerifiedFactor_shouldReturnAAL2() async throws {
    var session = Session.validSession

    // access token with aal token
    session.accessToken =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyLCJhYWwiOiJhYWwxIiwiYW1yIjpbeyJtZXRob2QiOiJ0b3RwIiwidGltZXN0YW1wIjoxNTE2MjM5MDIyfSx7Im1ldGhvZCI6InBob25lIiwidGltZXN0YW1wIjoxNTE2MjM5MDIyfV19.OQy2SmA1hcw9V5wrY-bvORjbFh5tWznLIfcMCqPu_6M"

    session.user.factors = [
      Factor(
        id: "1",
        friendlyName: nil,
        factorType: "totp",
        status: .verified,
        createdAt: Date(),
        updatedAt: Date()
      )
    ]

    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(session)

    let aal = try await sut.mfa.getAuthenticatorAssuranceLevel()

    expectNoDifference(
      aal,
      AuthMFAGetAuthenticatorAssuranceLevelResponse(
        currentLevel: "aal1",
        nextLevel: "aal2",
        currentAuthenticationMethods: [
          AMREntry(
            method: "totp",
            timestamp: 1_516_239_022
          ),
          AMREntry(
            method: "phone",
            timestamp: 1_516_239_022
          ),
        ]
      )
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/admin/users/859F402D-B3DE-4105-A1B9-932836D9193B",
          body: MockData.user)
      ], scope: .test))
  func getUserById() async throws {
    let id = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
    let sut = makeSUT()

    let user = try await sut.admin.getUserById(id)

    expectNoDifference(user.id, id)
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .put, "http://localhost:54321/auth/v1/admin/users/859F402D-B3DE-4105-A1B9-932836D9193B",
          body: MockData.user)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(#"{"phone":"1234567890","user_metadata":{"full_name":"John Doe"}}"#),
      ],
      scope: .test))
  func updateUserById() async throws {
    let id = UUID(uuidString: "859f402d-b3de-4105-a1b9-932836d9193b")!
    let sut = makeSUT()

    let attributes = AdminUserAttributes(
      phone: "1234567890",
      userMetadata: [
        "full_name": "John Doe"
      ]
    )

    let user = try await sut.admin.updateUserById(id, attributes: attributes)

    expectNoDifference(user.id, id)
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, "http://localhost:54321/auth/v1/admin/users", body: MockData.user)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(
          #"{"email":"test@example.com","password":"password","password_hash":"password","phone":"1234567890"}"#
        ),
      ],
      scope: .test))
  func createUser() async throws {
    let sut = makeSUT()

    let attributes = AdminUserAttributes(
      email: "test@example.com",
      password: "password",
      passwordHash: "password",
      phone: "1234567890"
    )

    _ = try await sut.admin.createUser(attributes: attributes)
  }

  //  func testGenerateLink_signUp() async throws {
  //    let sut = makeSUT()
  //
  //    let user = User(fromMockNamed: "user")
  //    let encoder = JSONEncoder.supabase()
  //    encoder.keyEncodingStrategy = .convertToSnakeCase
  //
  //    let userData = try encoder.encode(user)
  //    var json = try JSONSerialization.jsonObject(with: userData, options: []) as! [String: Any]
  //
  //    json["action_link"] = "https://example.com/auth/v1/verify?type=signup&token={hashed_token}&redirect_to=https://example.com"
  //    json["email_otp"] = "123456"
  //    json["hashed_token"] = "hashed_token"
  //    json["redirect_to"] = "https://example.com"
  //    json["verification_type"] = "signup"
  //
  //    let responseData = try JSONSerialization.data(withJSONObject: json)
  //
  //    Mock(
  //      url: clientURL.appendingPathComponent("admin/generate_link"),
  //      statusCode: 200,
  //      data: [
  //        .post: responseData
  //      ]
  //    )
  //    .register()
  //
  //    let link = try await sut.admin.generateLink(
  //      params: .signUp(
  //        email: "test@example.com",
  //        password: "password",
  //        data: ["full_name": "John Doe"]
  //      )
  //    )
  //
  //    expectNoDifference(
  //      link.properties.actionLink.absoluteString,
  //      "https://example.com/auth/v1/verify?type=signup&token={hashed_token}&redirect_to=https://example.com".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
  //    )
  //  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/admin/invite?redirect_to=https://example.com",
          body: MockData.user)
      ],
      matching: [
        .method, .path, .query,
        matchingBody(#"{"data":{"full_name":"John Doe"},"email":"test@example.com"}"#),
      ],
      scope: .test))
  func inviteUserByEmail() async throws {
    let sut = makeSUT()

    _ = try await sut.admin.inviteUserByEmail(
      "test@example.com",
      data: ["full_name": "John Doe"],
      redirectTo: URL(string: "https://example.com")
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/user", status: 403,
          body: Data(
            """
            {
              "error_code": "session_not_found",
              "message": "Session not found"
            }
            """.utf8))
      ], matching: [.method, .path, .query], scope: .test))
  func removeSessionAndSignoutIfSessionNotFoundErrorReturned() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.validSession)

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.user()
          Issue.record("Expected failure")
        } catch {
          #expect(error as? AuthError == .sessionMissing)
        }
      },
      expectedEvents: [.initialSession, .signedOut]
    )

    #expect(Dependencies[sut.clientID].sessionStorage.get() == nil)
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/token?grant_type=refresh_token", status: 403,
          body: Data(
            """
            {
              "error_code": "refresh_token_not_found",
              "message": "Invalid Refresh Token: Refresh Token Not Found"
            }
            """.utf8))
      ], matching: [.method, .path, .query], scope: .test))
  func removeSessionAndSignoutIfRefreshTokenNotFoundErrorReturned() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.expiredSession)

    let expectedEvents = [AuthChangeEvent.signedOut, .initialSession]

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.session
          Issue.record("Expected failure")
        } catch {
          #expect(error as? AuthError == .sessionMissing)
        }
      },
      expectedEvents: expectedEvents
    )

    #expect(Dependencies[sut.clientID].sessionStorage.get() == nil)
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/token?grant_type=refresh_token", status: 403,
          body: Data(
            """
            {
              "error_code": "refresh_token_not_found",
              "message": "Invalid Refresh Token: Refresh Token Not Found"
            }
            """.utf8))
      ], matching: [.method, .path, .query], scope: .test))
  func
    removeSessionAndSignoutIfRefreshTokenNotFoundErrorReturned_withEmitLocalSessionAsInitialSession()
    async throws
  {
    let sut = makeSUT(emitLocalSessionAsInitialSession: true)

    Dependencies[sut.clientID].sessionStorage.store(.expiredSession)

    let expectedEvents = [AuthChangeEvent.initialSession, .signedOut]

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        do {
          _ = try await sut.session
          Issue.record("Expected failure")
        } catch {
          #expect(error as? AuthError == .sessionMissing)
        }
      },
      expectedEvents: expectedEvents
    )

    #expect(Dependencies[sut.clientID].sessionStorage.get() == nil)
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/token?grant_type=refresh_token",
          body: try! AuthClient.Configuration.jsonEncoder.encode(Session.validSession))
      ], scope: .test))
  func refreshToken() async throws {
    let sut = makeSUT()

    Dependencies[sut.clientID].sessionStorage.store(.expiredSession)

    let expectedEvents = [AuthChangeEvent.tokenRefreshed, .initialSession]

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        _ = try await sut.session
      },
      expectedEvents: expectedEvents
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, "http://localhost:54321/auth/v1/token?grant_type=refresh_token",
          body: try! AuthClient.Configuration.jsonEncoder.encode(Session.validSession))
      ], scope: .test))
  func refreshToken_withEmitLocalSessionAsInitialSession() async throws {
    let sut = makeSUT(emitLocalSessionAsInitialSession: true)

    Dependencies[sut.clientID].sessionStorage.store(.expiredSession)

    let expectedEvents = [AuthChangeEvent.initialSession, .tokenRefreshed]

    try await assertAuthStateChanges(
      sut: sut,
      action: {
        _ = try await sut.session
      },
      expectedEvents: expectedEvents
    )
  }

  // MARK: - getClaims Tests

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/user",
          body: try! AuthClient.Configuration.jsonEncoder.encode(User(fromMockNamed: "user")))
      ], scope: .test))
  func getClaims_withHS256JWT_shouldFallbackAndReturnClaims() async throws {
    // HS256 JWT (symmetric algorithm) - will use server-side verification
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.4Adcj0vZKqXRB_mPpDVkWvB3xw7yHYjpzGJLKFQjKEc"

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt)

    #expect(result.claims.sub == "1234567890")
    #expect(result.claims.iss == "http://localhost:54321/auth/v1")
    if case .string(let aud) = result.claims.aud {
      #expect(aud == "authenticated")
    } else {
      Issue.record("Expected string audience")
    }
    #expect(result.claims.role == "authenticated")
    #expect(result.header.alg == "HS256")
    #expect(result.header.kid == nil)
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/user",
          body: try! AuthClient.Configuration.jsonEncoder.encode(User(fromMockNamed: "user")))
      ], scope: .test))
  func getClaims_withoutJWT_shouldUseSessionAccessToken() async throws {
    // HS256 JWT from session
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.4Adcj0vZKqXRB_mPpDVkWvB3xw7yHYjpzGJLKFQjKEc"

    var session = Session.validSession
    session.accessToken = jwt

    let sut = makeSUT()
    Dependencies[sut.clientID].sessionStorage.store(session)

    let result = try await sut.getClaims()

    #expect(result.claims.sub == "1234567890")
    #expect(result.claims.role == "authenticated")
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/user",
          body: try! AuthClient.Configuration.jsonEncoder.encode(User(fromMockNamed: "user")))
      ], scope: .test))
  func getClaims_withProvidedJWKS_shouldStillFallbackForES256() async throws {
    // ES256 is not yet supported client-side, so it will fallback to server even with JWKS
    let jwt =
      "eyJhbGciOiJFUzI1NiIsImtpZCI6InRlc3Qta2lkIiwidHlwIjoiSldUIn0.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.dummysignature"

    // JWK is Codable, no custom init needed
    let jwkDict: [String: Any] = [
      "kty": "EC",
      "kid": "test-kid",
      "alg": "ES256",
      "crv": "P-256",
      "x": "MKBCTNIcKUSDii11ySs3526iDZ8AiTo7Tu6KPAqv7D4",
      "y": "4Etl6SRW2YiLUrN5vfvVHuhp7x8PxltmWWlbbM4IFyM",
    ]

    let jwkData = try JSONSerialization.data(withJSONObject: jwkDict)
    let jwk = try AuthClient.Configuration.jsonDecoder.decode(JWK.self, from: jwkData)
    let jwks = JWKS(keys: [jwk])

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt, options: GetClaimsOptions(jwks: jwks))

    #expect(result.claims.sub == "1234567890")
    #expect(result.claims.role == "authenticated")
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/user",
          body: try! AuthClient.Configuration.jsonEncoder.encode(User(fromMockNamed: "user")))
      ], scope: .test))
  func getClaims_withES256JWT_shouldFallbackToServerVerification() async throws {
    // ES256 JWT without kid - will fallback to server
    let jwt =
      "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.dummysignature"

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt)

    #expect(result.claims.sub == "1234567890")
    #expect(result.claims.role == "authenticated")
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/.well-known/jwks.json",
          body: try! AuthClient.Configuration.jsonEncoder.encode(
            JWKS(keys: [
              try! AuthClient.Configuration.jsonDecoder.decode(
                JWK.self,
                from: JSONSerialization.data(withJSONObject: [
                  "kty": "RSA",
                  "kid": "different-kid",
                  "alg": "RS256",
                  "n": "modulus",
                  "e": "AQAB",
                ] as [String: Any]))
            ]))),
        Stub(
          .get, "http://localhost:54321/auth/v1/user",
          body: try! AuthClient.Configuration.jsonEncoder.encode(User(fromMockNamed: "user"))),
      ],
      matching: [.method, .path],
      scope: .test))
  func getClaims_withRS256JWT_whenJWKNotFound_shouldFallbackToServerVerification() async throws {
    // RS256 JWT with kid but key not in JWKS - will try to fetch JWKS, not find it, then fallback to server
    let jwt =
      "eyJhbGciOiJSUzI1NiIsImtpZCI6InRlc3Qta2lkIiwidHlwIjoiSldUIn0.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.dummysignature"

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt)

    #expect(result.claims.sub == "1234567890")
    #expect(result.claims.role == "authenticated")
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/user",
          body: try! AuthClient.Configuration.jsonEncoder.encode(User(fromMockNamed: "user")))
      ], scope: .test))
  func getClaims_withNoKidInHeader_shouldFallbackToServerVerification() async throws {
    // JWT without kid - cannot look up in JWKS
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiI5ODc2NTQzMjEiLCJpc3MiOiJodHRwOi8vbG9jYWxob3N0OjU0MzIxL2F1dGgvdjEiLCJhdWQiOiJhdXRoZW50aWNhdGVkIiwiZXhwIjo5OTk5OTk5OTk5LCJpYXQiOjE1MTYyMzkwMjIsInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.YT0NvH-jYKCiN-wrAVcMmTIxZkQ3OtqTVFjJAqGcRuw"

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt)

    #expect(result.claims.sub == "987654321")
    #expect(result.claims.role == "authenticated")
  }

  @Test
  func getClaims_withoutJWTAndNoSession_shouldThrowSessionMissing() async throws {
    let sut = makeSUT()

    do {
      _ = try await sut.getClaims()
      Issue.record("Expected sessionMissing error")
    } catch let error as AuthError {
      guard case .sessionMissing = error else {
        Issue.record("Expected sessionMissing error, got \(error)")
        return
      }
    } catch {
      Issue.record("Expected AuthError, got \(error)")
    }
  }

  @Test
  func getClaims_withInvalidJWTStructure_shouldThrowJWTVerificationFailed() async throws {
    let invalidJWT = "invalid.jwt.token"

    let sut = makeSUT()

    do {
      _ = try await sut.getClaims(jwt: invalidJWT)
      Issue.record("Expected jwtVerificationFailed error")
    } catch let error as AuthError {
      guard case .jwtVerificationFailed(let message) = error else {
        Issue.record("Expected jwtVerificationFailed error, got \(error)")
        return
      }
      #expect(message == "Invalid JWT structure")
    } catch {
      Issue.record("Expected AuthError, got \(error)")
    }
  }

  @Test
  func getClaims_withExpiredJWT_shouldThrowJWTVerificationFailed() async throws {
    // JWT with exp in the past
    let expiredJWT =
      "eyJhbGciOiJFUzI1NiIsImtpZCI6InRlc3Qta2lkIiwidHlwIjoiSldUIn0.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6MTUxNjIzOTAyMiwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.MEYCIQDmtLy0PF_lR7rJQHyKLmJKp1xFKECfVvGTBcXiVnz0jAIhAOoXZJ3kHSA2MqL1XhcUy8dWOZCr6zWCN_FXsP8qKfPR"

    let sut = makeSUT()

    do {
      _ = try await sut.getClaims(jwt: expiredJWT)
      Issue.record("Expected jwtVerificationFailed error")
    } catch let error as AuthError {
      guard case .jwtVerificationFailed(let message) = error else {
        Issue.record("Expected jwtVerificationFailed error, got \(error)")
        return
      }
      #expect(message == "JWT has expired")
    } catch {
      Issue.record("Expected AuthError, got \(error)")
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/user",
          body: try! AuthClient.Configuration.jsonEncoder.encode(User(fromMockNamed: "user")))
      ], scope: .test))
  func getClaims_withExpiredJWTAndAllowExpired_shouldReturnClaims() async throws {
    // JWT with exp in the past but allowExpired option - falls back to server
    let expiredJWT =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6MTUxNjIzOTAyMiwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.aN0HLYHkp7nKZp4xWvBaDqSrCFBxk2tq0KZc4BXGqYs"

    let sut = makeSUT()

    let result = try await sut.getClaims(
      jwt: expiredJWT,
      options: GetClaimsOptions(allowExpired: true)
    )

    #expect(result.claims.sub == "1234567890")
    #expect(result.claims.exp == 1_516_239_022)
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/user", status: 401,
          body: try! AuthClient.Configuration.jsonEncoder.encode([
            "error": "invalid_token",
            "error_description": "Invalid JWT",
          ]))
      ], scope: .test))
  func getClaims_whenServerRejectsJWT_shouldThrowError() async throws {
    // HS256 JWT that will be verified server-side
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJyb2xlIjoiYXV0aGVudGljYXRlZCJ9.4Adcj0vZKqXRB_mPpDVkWvB3xw7yHYjpzGJLKFQjKEc"

    let sut = makeSUT()

    do {
      _ = try await sut.getClaims(jwt: jwt)
      Issue.record("Expected error from server")
    } catch {
      // Expected to fail
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/user",
          body: try! AuthClient.Configuration.jsonEncoder.encode(User(fromMockNamed: "user")))
      ], scope: .test))
  func getClaims_withComplexClaims_shouldDecodeAllFields() async throws {
    // JWT with multiple claim fields
    // HS256 so it falls back to server verification
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjoiYXV0aGVudGljYXRlZCIsImV4cCI6OTk5OTk5OTk5OSwiaWF0IjoxNTE2MjM5MDIyLCJuYmYiOjE1MTYyMzkwMjIsImp0aSI6InRlc3QtanRpIiwicm9sZSI6ImF1dGhlbnRpY2F0ZWQiLCJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20iLCJwaG9uZSI6IisxMjM0NTY3ODkwIn0.dBYm1Y-TfRjPsxw_gXqHB5zGHSH9hXS0OeFN_wL8HbA"

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt)

    #expect(result.claims.sub == "1234567890")
    #expect(result.claims.iss == "http://localhost:54321/auth/v1")
    if case .string(let aud) = result.claims.aud {
      #expect(aud == "authenticated")
    } else {
      Issue.record("Expected string audience")
    }
    #expect(result.claims.exp == 9_999_999_999)
    #expect(result.claims.iat == 1_516_239_022)
    #expect(result.claims.nbf == 1_516_239_022)
    #expect(result.claims.jti == "test-jti")
    #expect(result.claims.role == "authenticated")
    #expect(result.claims.email == "test@example.com")
    #expect(result.claims.phone == "+1234567890")
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .get, "http://localhost:54321/auth/v1/user",
          body: try! AuthClient.Configuration.jsonEncoder.encode(User(fromMockNamed: "user")))
      ], scope: .test))
  func getClaims_withArrayAudience_shouldDecodeCorrectly() async throws {
    // JWT with audience as array
    let jwt =
      "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwiaXNzIjoiaHR0cDovL2xvY2FsaG9zdDo1NDMyMS9hdXRoL3YxIiwiYXVkIjpbImF1dGhlbnRpY2F0ZWQiLCJzZXJ2aWNlLXJvbGUiXSwiZXhwIjo5OTk5OTk5OTk5LCJpYXQiOjE1MTYyMzkwMjIsInJvbGUiOiJhdXRoZW50aWNhdGVkIn0.Jz-lHQoR2VsQ_vX8wKyN7mPxT4aU9cF1bYsHqGdWlIk"

    let sut = makeSUT()

    let result = try await sut.getClaims(jwt: jwt)

    #expect(result.claims.sub == "1234567890")
    #expect(result.claims.aud != nil)
  }

  private func makeSUT(
    flowType: AuthFlowType = .pkce, emitLocalSessionAsInitialSession: Bool = false
  ) -> AuthClient {
    let encoder = AuthClient.Configuration.jsonEncoder
    encoder.outputFormatting = [.sortedKeys]

    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: [
        "apikey":
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
      ],
      flowType: flowType,
      localStorage: storage,
      logger: nil,
      encoder: encoder,
      fetch: { try await Replay.session.data(for: $0) },
      emitLocalSessionAsInitialSession: emitLocalSessionAsInitialSession
    )

    let sut = AuthClient(configuration: configuration)

    Dependencies[sut.clientID].pkce.generateCodeVerifier = {
      "nt_xCJhJXUsIlTmbE_b0r3VHDKLxFTAwXYSj1xF3ZPaulO2gejNornLLiW_C3Ru4w-5lqIh1XE2LTOsSKrj7iA"
    }

    Dependencies[sut.clientID].pkce.generateCodeChallenge = { _ in
      "hgJeigklONUI1pKSS98MIAbtJGaNu0zJU1iSiFOn2lY"
    }

    return sut
  }

  /// Convenience method for testing auth state changes and asserting events
  /// - Parameters:
  ///   - sut: The AuthClient instance to monitor
  ///   - action: The async action to perform that should trigger events
  ///   - expectedEvents: Array of expected AuthChangeEvent values
  ///   - expectedSessions: Array of expected Session values (optional)
  private func assertAuthStateChanges<T>(
    sut: AuthClient,
    action: () async throws -> T,
    expectedEvents: [AuthChangeEvent],
    expectedSessions: [Session?]? = nil,
    timeout: TimeInterval = 2,
    fileID: StaticString = #fileID,
    filePath: StaticString = #filePath,
    line: UInt = #line,
    column: UInt = #column
  ) async throws -> T {
    let receivedEvents = LockIsolated([(event: AuthChangeEvent, session: Session?)]())
    let finished = LockIsolated(false)

    Task {
      for await change in sut.authStateChanges {
        if finished.value {
          Issue.record("Received event '\(change.event)' after it finished.")
        }
        receivedEvents.withValue { $0.append(change) }
      }
    }

    await Task.megaYield()

    let result = try await action()

    try await withTimeout(interval: timeout) {
      defer { finished.setValue(true) }
      while receivedEvents.count < expectedEvents.count {
        await Task.yield()
      }
    }

    await Task.megaYield()

    expectNoDifference(
      receivedEvents.value.map(\.event),
      expectedEvents,
      fileID: fileID,
      filePath: filePath,
      line: line,
      column: column
    )

    if let expectedSessions = expectedSessions {
      expectNoDifference(
        receivedEvents.value.map(\.session),
        expectedSessions,
        fileID: fileID,
        filePath: filePath,
        line: line,
        column: column
      )
    }

    return result
  }
}

/// Matches a request whose raw JSON body decodes structurally-equal to `expected`, so
/// write-endpoint tests can assert on request-body content (key order and whitespace don't
/// matter) without needing exact byte-for-byte matching.
///
/// `URLSession` may expose the body via `httpBody` or, once the request has been handed to the
/// loading system (as happens with Replay's `PlaybackURLProtocol`), via `httpBodyStream` — read
/// whichever is present.
private func matchingBody(_ expectedJSON: String) -> Matcher {
  .custom { request, _ in
    let data: Data?
    if let body = request.httpBody {
      data = body
    } else if let stream = request.httpBodyStream {
      data = Data(readingAllOf: stream)
    } else {
      data = nil
    }
    guard let data else { return false }
    let actual = try? JSONDecoder().decode(AnyJSON.self, from: data)
    let expected = try? JSONDecoder().decode(AnyJSON.self, from: Data(expectedJSON.utf8))
    return actual == expected
  }
}

extension Data {
  fileprivate init(readingAllOf stream: InputStream) {
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: bufferSize)
      if read > 0 {
        data.append(buffer, count: read)
      } else {
        break
      }
    }
    self = data
  }
}

enum MockData {
  static let listUsersResponse = try! Data(
    contentsOf: Bundle.module.url(forResource: "list-users-response", withExtension: "json")!
  )

  static let session = try! Data(
    contentsOf: Bundle.module.url(forResource: "session", withExtension: "json")!
  )

  static let user = try! Data(
    contentsOf: Bundle.module.url(forResource: "user", withExtension: "json")!
  )

  static let anonymousSignInResponse = try! Data(
    contentsOf: Bundle.module.url(forResource: "anonymous-sign-in-response", withExtension: "json")!
  )
}

extension HTTPResponse {
  static func stub(
    _ body: String = "",
    code: Int = 200,
    headers: [String: String]? = nil
  ) -> HTTPResponse {
    HTTPResponse(
      data: body.data(using: .utf8)!,
      response: HTTPURLResponse(
        url: clientURL,
        statusCode: code,
        httpVersion: nil,
        headerFields: headers
      )!
    )
  }

  static func stub(
    fromFileName fileName: String,
    code: Int = 200,
    headers: [String: String]? = nil
  ) -> HTTPResponse {
    HTTPResponse(
      data: json(named: fileName),
      response: HTTPURLResponse(
        url: clientURL,
        statusCode: code,
        httpVersion: nil,
        headerFields: headers
      )!
    )
  }

  static func stub(
    _ value: some Encodable,
    code: Int = 200,
    headers: [String: String]? = nil
  ) -> HTTPResponse {
    HTTPResponse(
      data: try! AuthClient.Configuration.jsonEncoder.encode(value),
      response: HTTPURLResponse(
        url: clientURL,
        statusCode: code,
        httpVersion: nil,
        headerFields: headers
      )!
    )
  }
}
