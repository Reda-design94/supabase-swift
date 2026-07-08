//
//  PostgrestBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 20/08/24.
//

import ConcurrencyExtras
import Foundation
import HTTPTypes
import Helpers
import Replay
import Testing

@testable import PostgREST

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

// `_clock` (Sources/Helpers/_Clock.swift) is a process-global mutable seam used to skip
// real sleep delays in the retry tests below. Serialize this suite so its tests don't race
// each other's clock swaps — Swift Testing runs `@Test`s in the same suite concurrently by
// default, unlike XCTest's implicit one-class-at-a-time execution. Use a class (not a struct)
// so `deinit` can restore the real clock afterward, mirroring the old `tearDown()` — leaving
// `_clock` swapped would leak into any other suite that runs later in the same process without
// its own defensive reset.
@Suite(.serialized)
final class PostgrestBuilderTests {
  let fixture = PostgrestQueryFixture()
  var url: URL { fixture.url }
  var sut: PostgrestClient { fixture.sut }

  init() {
    #if DEBUG
      _clock = ImmediateRetryTestClock()
    #endif
  }

  deinit {
    #if DEBUG
      _clock = ContinuousClock()
    #endif
  }

  @Test
  func customHeaderOnAPerCallBasis() throws {
    let url = URL(string: "http://localhost:54321/rest/v1")!
    let postgrest1 = PostgrestClient(url: url, headers: ["apikey": "foo"], logger: nil)
    let postgrest2 = try postgrest1.rpc("void_func").setHeader(name: .init("apikey")!, value: "bar")

    // Original client object isn't affected
    #expect(
      postgrest1.from("users").select().mutableState.request.headers[.init("apikey")!] == "foo")
    // Derived client object uses new header value
    #expect(postgrest2.mutableState.request.headers[.init("apikey")!] == "bar")
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users", 400, [:],
          {
            """
            {
              "message": "Bad Request"
            }
            """
          })
      ], matching: [.method, .path], scope: .test))
  func executeWithNonSuccessStatusCode() async throws {
    do {
      try await sut
        .from("users")
        .select()
        .execute()
    } catch let error as PostgrestError {
      #expect(error.message == "Bad Request")
    }
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users", 400, [:]) { "Bad Request" }
      ], matching: [.method, .path], scope: .test))
  func executeWithNonJSONError() async throws {
    do {
      try await sut
        .from("users")
        .select()
        .execute()
    } catch let error as HTTPError {
      #expect(error.data == Data("Bad Request".utf8))
      #expect(error.response.statusCode == 400)
    }
  }

  @Test(
    .replay(
      stubs: [
        .head("http://localhost:54321/rest/v1/users?select=%2A", 200, [:])
      ], scope: .test))
  func executeWithHead() async throws {
    try await sut.from("users")
      .select()
      .execute(options: FetchOptions(head: true))
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=%2A", 200, [:]) { "[]" }
      ], scope: .test))
  func executeWithCount() async throws {
    try await sut.from("users")
      .select()
      .execute(options: FetchOptions(count: .exact))
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=%2A", 200, [:]) { "[]" }
      ], scope: .test))
  func executeWithCustomSchema() async throws {
    try await sut
      .schema("private")
      .from("users")
      .select()
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .head("http://localhost:54321/rest/v1/users?select=%2A", 200, [:])
      ], scope: .test))
  func executeWithCustomSchemaAndHeadMethod() async throws {
    try await sut
      .schema("private")
      .from("users")
      .select()
      .execute(options: FetchOptions(head: true))
  }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/rest/v1/users", 201, [:]) { "" }
      ], matching: [.method, .path], scope: .test))
  func executeWithCustomSchemaAndPostMethod() async throws {
    try await sut
      .schema("private")
      .from("users")
      .insert(["username": "test"])
      .execute()
  }

  @Test
  func setHeader() {
    let query = sut.from("users")
      .setHeader(name: "key", value: "value")

    #expect(query.mutableState.request.headers[.init("key")!] == "value")
  }

  // MARK: - Retry tests

  @Test
  func retryOn520ForGETRequest() async throws {
    struct MutableState {
      var callCount = 0
      var capturedHeaders = [[String: String]]()
    }

    let state = LockIsolated(MutableState())

    let sut = Self.makeSUTWithCustomFetch { request in
      state.withValue { state in
        state.callCount += 1
        state.capturedHeaders.append(
          Dictionary(uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { $0 }))

        if state.callCount < 3 {
          return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
        }
        return (Data("[]".utf8), Self.makeHTTPURLResponse(statusCode: 200))
      }
    }

    let result: PostgrestResponse<[User]> = try await sut.from("users").select().execute()

    state.withValue { state in
      #expect(state.callCount == 3)
      #expect(state.capturedHeaders[0]["X-Retry-Count"] == nil)
      #expect(state.capturedHeaders[1]["X-Retry-Count"] == "1")
      #expect(state.capturedHeaders[2]["X-Retry-Count"] == "2")
    }
    #expect(result.value.isEmpty)
  }

  @Test
  func retryOn520ForHEADRequest() async throws {
    let callCount = LockIsolated(0)

    let sut = Self.makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      if callCount.value < 2 {
        return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
      }
      return (Data(), Self.makeHTTPURLResponse(statusCode: 200))
    }

    try await sut.from("users").select().execute(options: FetchOptions(head: true))
    #expect(callCount.value == 2)
  }

  @Test
  func noRetryOn520ForPOSTRequest() async throws {
    let callCount = LockIsolated(0)

    let sut = Self.makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
    }

    do {
      try await sut.from("users").insert(["username": "test"]).execute()
      Issue.record("Expected error to be thrown")
    } catch {
      #expect(callCount.value == 1)
    }
  }

  @Test
  func noRetryOnNon520ErrorForGET() async throws {
    let callCount = LockIsolated(0)

    let sut = Self.makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      return (
        Data(#"{"message":"Bad Request"}"#.utf8),
        Self.makeHTTPURLResponse(statusCode: 400)
      )
    }

    do {
      try await sut.from("users").select().execute()
      Issue.record("Expected error to be thrown")
    } catch let error as PostgrestError {
      #expect(callCount.value == 1)
      #expect(error.message == "Bad Request")
    }
  }

  @Test
  func retryOn503ForGETRequest() async throws {
    let callCount = LockIsolated(0)

    let sut = Self.makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      if callCount.value < 2 {
        return (Data(), Self.makeHTTPURLResponse(statusCode: 503))
      }
      return (Data("[]".utf8), Self.makeHTTPURLResponse(statusCode: 200))
    }

    let result: PostgrestResponse<[User]> = try await sut.from("users").select().execute()
    #expect(callCount.value == 2)
    #expect(result.value.isEmpty)
  }

  @Test
  func retryOn503ForHEADRequest() async throws {
    let callCount = LockIsolated(0)

    let sut = Self.makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      if callCount.value < 2 {
        return (Data(), Self.makeHTTPURLResponse(statusCode: 503))
      }
      return (Data(), Self.makeHTTPURLResponse(statusCode: 200))
    }

    try await sut.from("users").select().execute(options: FetchOptions(head: true))
    #expect(callCount.value == 2)
  }

  @Test
  func retryOnNetworkErrorForGET() async throws {
    let callCount = LockIsolated(0)

    let sut = Self.makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      if callCount.value < 2 {
        throw URLError(.networkConnectionLost)
      }
      return (Data("[]".utf8), Self.makeHTTPURLResponse(statusCode: 200))
    }

    let result: PostgrestResponse<[User]> = try await sut.from("users").select().execute()
    #expect(callCount.value == 2)
    #expect(result.value.isEmpty)
  }

  @Test
  func noRetryOnNetworkErrorForPOST() async throws {
    let callCount = LockIsolated(0)

    let sut = Self.makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      throw URLError(.networkConnectionLost)
    }

    do {
      try await sut.from("users").insert(["username": "test"]).execute()
      Issue.record("Expected error to be thrown")
    } catch {
      #expect(callCount.value == 1)
    }
  }

  @Test
  func exhaustAllRetries() async throws {
    let callCount = LockIsolated(0)

    let sut = Self.makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
    }

    do {
      try await sut.from("users").select().execute()
      Issue.record("Expected error to be thrown")
    } catch {
      #expect(callCount.value == 4)  // 1 initial + 3 retries
    }
  }

  @Test
  func perRequestRetryDisabled() async throws {
    let callCount = LockIsolated(0)

    let sut = Self.makeSUTWithCustomFetch { _ in
      callCount.withValue { $0 += 1 }
      return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
    }

    do {
      try await sut.from("users").select().retry(enabled: false).execute()
      Issue.record("Expected error to be thrown")
    } catch {
      #expect(callCount.value == 1)
    }
  }

  @Test
  func clientLevelRetryDisabled() async throws {
    let callCount = LockIsolated(0)

    let sut = Self.makeSUTWithCustomFetch(retryEnabled: false) { _ in
      callCount.withValue { $0 += 1 }
      return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
    }

    do {
      try await sut.from("users").select().execute()
      Issue.record("Expected error to be thrown")
    } catch {
      #expect(callCount.value == 1)
    }
  }

  @Test
  func retryEnabledPerRequestOverridesClientDisabled() async throws {
    let callCount = LockIsolated(0)

    let sut = Self.makeSUTWithCustomFetch(retryEnabled: false) { _ in
      callCount.withValue { $0 += 1 }
      if callCount.value < 2 {
        return (Data(), Self.makeHTTPURLResponse(statusCode: 520))
      }
      return (Data("[]".utf8), Self.makeHTTPURLResponse(statusCode: 200))
    }

    let result: PostgrestResponse<[User]> = try await sut.from("users").select().retry(
      enabled: true
    )
    .execute()
    #expect(callCount.value == 2)
    #expect(result.value.isEmpty)
  }

  // MARK: - Helpers

  private static func makeSUTWithCustomFetch(
    retryEnabled: Bool = true,
    fetch: @escaping PostgrestClient.FetchHandler
  ) -> PostgrestClient {
    PostgrestClient(url: PostgrestQueryFixture.url, fetch: fetch, retryEnabled: retryEnabled)
  }

  private static func makeHTTPURLResponse(statusCode: Int) -> HTTPURLResponse {
    HTTPURLResponse(
      url: PostgrestQueryFixture.url, statusCode: statusCode, httpVersion: nil, headerFields: nil
    )!
  }
}

/// A no-op clock for tests — skips all sleep delays so retry tests run instantly.
struct ImmediateRetryTestClock: Clock {
  var now: ContinuousClock.Instant { ContinuousClock().now }
  var minimumResolution: ContinuousClock.Instant.Duration { ContinuousClock().minimumResolution }

  func sleep(until deadline: ContinuousClock.Instant, tolerance: Duration?) async throws {}
}
