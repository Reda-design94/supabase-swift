//
//  PostgrestFilterBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Foundation
import PostgREST
import Replay
import Testing

private let usersStub: [Stub] = [
  .get("http://localhost:54321/rest/v1/users", 200, [:]) { "[]" }
]

@Suite
struct PostgrestFilterBuilderTests {
  let fixture = PostgrestQueryFixture()
  var url: URL { fixture.url }
  var sut: PostgrestClient { fixture.sut }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func notFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .not("status", operator: .eq, value: "OFFLINE")
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func orFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .or("status.eq.OFFLINE,username.eq.test")
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func orFilterWithReferencedTable() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .or("public.eq.true,recipient_id.eq.1", referencedTable: "messages")
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func containsFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .contains("address", value: ["postcode": 90210])
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func textSearchFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .textSearch("description", query: "programmer", config: "english")
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func multipleFilters() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .gte("age", value: 18)
      .eq("status", value: "active")
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func likeFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .like("email", pattern: "%@example.com")
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func iLikeFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .ilike("email", pattern: "%@EXAMPLE.COM")
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func isFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .is("deleted_at", value: nil)
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func inFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .in("status", values: ["active", "pending"])
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func inFilterQuotesValuesWithReservedCharacters() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .in("tags", values: ["a,b", "c(d)", "plain"])
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func containedByFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .containedBy("roles", value: ["admin", "user"])
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func rangeFilters() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .rangeLt("age_range", range: "[18,25)")
      .rangeGt("other_range", range: "[25,35)")
      .rangeGte("third_range", range: "[35,45)")
      .rangeLte("fourth_range", range: "[45,55)")
      .rangeAdjacent("fifth_range", range: "[55,65)")
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func overlapsFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .overlaps("schedule", value: ["9:00", "17:00"])
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func matchFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .match(["status": "active", "role": "admin"])
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func filterEscapeHatch() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .filter("created_at", operator: "gt", value: "2023-01-01")
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func neqFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .neq("status", value: "inactive")
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func gtFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .gt("age", value: 21)
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func ltFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .lt("age", value: 65)
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func lteFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .lte("age", value: 65)
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func likeAllOfFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .likeAllOf("name", patterns: ["%test%", "%user%"])
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func likeAnyOfFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .likeAnyOf("name", patterns: ["%test%", "%user%"])
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func iLikeAllOfFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .iLikeAllOf("name", patterns: ["%TEST%", "%USER%"])
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func iLikeAnyOfFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .iLikeAnyOf("name", patterns: ["%TEST%", "%USER%"])
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func ftsFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .fts("description", query: "programmer")
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func regexMatchFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .match("email", pattern: "^.+@.+\\..+$")
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func regexImatchFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .imatch("name", pattern: "^john")
      .execute()
  }

  @Test(.replay(stubs: usersStub, matching: [.method, .path], scope: .test))
  func isDistinctFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .isDistinct("status", value: "null")
      .execute()
  }
}
