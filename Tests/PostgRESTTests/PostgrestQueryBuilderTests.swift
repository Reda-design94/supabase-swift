//
//  PostgrestQueryBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Foundation
import PostgREST
import Replay
import Testing

@Suite
struct PostgrestQueryBuilderTests {
  let fixture = PostgrestQueryFixture()
  var url: URL { fixture.url }
  var sut: PostgrestClient { fixture.sut }

  /// Matches a request whose raw JSON body equals `expected` exactly.
  ///
  /// `Stub` only carries a response body, not an expected request body, so the default
  /// `.body` matcher (which compares against a stub-derived candidate with no `httpBody`)
  /// can't verify this. This reads the *incoming* request directly instead.
  private static func matchingBody(_ expected: String) -> Matcher {
    .custom { request, _ in request.bodyData == Data(expected.utf8) }
  }

  @Test
  func setAuth() {
    #expect(sut.configuration.headers["Authorization"] == nil)
    sut.setAuth("token")
    #expect(sut.configuration.headers["Authorization"] == "Bearer token")

    sut.setAuth(nil)
    #expect(sut.configuration.headers["Authorization"] == nil)
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A", 200,
          [:],
          {
            """
            [
              {
                "id": 1,
                "username": "supabase"
              }
            ]
            """
          })
      ], scope: .test))
  func select() async throws {
    let users =
      try await sut
      .from("users")
      .select()
      .execute()
      .value as [User]

    #expect(users[0].id == 1)
    #expect(users[0].username == "supabase")
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=somecolumn", 200, [:]) { "" }
      ], scope: .test))
  func selectWithWhitespaceInQuery() async throws {
    try await sut
      .from("users")
      .select("some column")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=some%22column%22", 200, [:]) { "" }
      ], scope: .test))
  func selectWithQuoteInQuery() async throws {
    try await sut
      .from("users")
      .select(#"some "column""#)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .head(
          "http://localhost:54321/rest/v1/users?select=%2A", 200, ["Content-Range": "0-9/10"])
      ], scope: .test))
  func selectWithCount() async throws {
    let count =
      try await sut
      .from("users")
      .select(head: true, count: .exact)
      .execute()
      .count

    #expect(count == 10)
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/rest/v1/users?columns=%22id%22%2C%22username%22", 201, [:]
        ) { "" }
      ],
      matching: [
        .method, .url,
        Self.matchingBody(
          #"[{"id":1,"username":"supabase"},{"id":1,"username":"supa"}]"#),
      ], scope: .test))
  func insert() async throws {
    try await sut
      .from("users")
      .insert(
        [
          User(id: 1, username: "supabase"),
          User(id: 1, username: "supa"),
        ],
        returning: .minimal,
        count: .estimated
      )
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/rest/v1/users?columns=%22a%2Cb%22", 201, [:]) { "" }
      ],
      matching: [.method, .url, Self.matchingBody(#"[{"a,b":1}]"#)],
      scope: .test))
  func insertQuotesColumnNameContainingReservedCharacter() async throws {
    try await sut
      .from("users")
      .insert([["a,b": 1]], returning: .minimal)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/rest/v1/users", 201, [:]) { "" }
      ],
      matching: [.method, .url, Self.matchingBody(#"{"id":1,"username":"supabase"}"#)],
      scope: .test))
  func insertWithExistingPreferHeader() async throws {
    try await sut
      .from("users")
      .setHeader(name: "Prefer", value: "existing=value")
      .insert(User(id: 1, username: "supabase"), returning: .minimal)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .patch("http://localhost:54321/rest/v1/users?id=eq.1", 201, [:]) { "" }
      ],
      matching: [.method, .url, Self.matchingBody(#"{"username":"supabase2"}"#)],
      scope: .test))
  func update() async throws {
    try await sut
      .from("users")
      .setHeader(name: "Prefer", value: "existing=value")
      .update(["username": "supabase2"], returning: .minimal, count: .planned)
      .eq("id", value: 1)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/rest/v1/users?on_conflict=username&columns=%22id%22%2C%22username%22",
          201, [:]
        ) { "" }
      ],
      matching: [
        .method, .url,
        Self.matchingBody(
          #"[{"id":1,"username":"admin"},{"id":2,"username":"supabase"}]"#),
      ], scope: .test))
  func upsert() async throws {
    try await sut
      .from("users")
      .setHeader(name: "Prefer", value: "existing=value")
      .upsert(
        [
          User(id: 1, username: "admin"),
          User(id: 2, username: "supabase"),
        ],
        onConflict: "username",
        returning: .minimal,
        count: .estimated
      )
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/rest/v1/users", 201, [:]) { "" }
      ],
      matching: [.method, .url, Self.matchingBody(#"{"id":1,"username":"admin"}"#)],
      scope: .test))
  func upsertIgnoreDuplicates() async throws {
    try await sut
      .from("users")
      .upsert(User(id: 1, username: "admin"), ignoreDuplicates: true)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .delete("http://localhost:54321/rest/v1/users?username=eq.supabase", 204, [:]) { "" }
      ], scope: .test))
  func delete() async throws {
    try await sut
      .from("users")
      .setHeader(name: "Prefer", value: "existing=value")
      .delete(count: .estimated)
      .eq("username", value: "supabase")
      .execute()
  }
}

extension URLRequest {
  /// The request body, read from `httpBody` or, when the request has been routed through a
  /// `URLProtocol` (as Replay's `PlaybackURLProtocol` does), from `httpBodyStream` — `URLSession`
  /// converts `httpBody` into a stream for protocol-intercepted requests, so `httpBody` alone
  /// reads back as `nil` by the time a `.custom` matcher observes the request.
  fileprivate var bodyData: Data? {
    if let httpBody {
      return httpBody
    }
    guard let stream = httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }

    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: bufferSize)
      if read <= 0 { break }
      data.append(buffer, count: read)
    }
    return data
  }
}
