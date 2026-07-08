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

@Suite
struct PostgrestFilterBuilderTests {
  let fixture = PostgrestQueryFixture()
  var url: URL { fixture.url }
  var sut: PostgrestClient { fixture.sut }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=%2A&status=not.eq.OFFLINE", 200, [:]) {
          "[]"
        }
      ], scope: .test))
  func notFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .not("status", operator: .eq, value: "OFFLINE")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&or=%28status.eq.OFFLINE%2Cusername.eq.test%29",
          200, [:]
        ) { "[]" }
      ], scope: .test))
  func orFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .or("status.eq.OFFLINE,username.eq.test")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&messages.or=%28public.eq.true%2Crecipient_id.eq.1%29",
          200, [:]
        ) { "[]" }
      ], scope: .test))
  func orFilterWithReferencedTable() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .or("public.eq.true,recipient_id.eq.1", referencedTable: "messages")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&address=cs.%7B%22postcode%22%3A90210%7D",
          200, [:]
        ) { "[]" }
      ], scope: .test))
  func containsFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .contains("address", value: ["postcode": 90210])
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&description=fts%28english%29.programmer",
          200, [:]
        ) { "[]" }
      ], scope: .test))
  func textSearchFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .textSearch("description", query: "programmer", config: "english")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&age=gte.18&status=eq.active", 200, [:]
        ) { "[]" }
      ], scope: .test))
  func multipleFilters() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .gte("age", value: 18)
      .eq("status", value: "active")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&email=like.%25%40example.com", 200, [:]
        ) { "[]" }
      ], scope: .test))
  func likeFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .like("email", pattern: "%@example.com")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&email=ilike.%25%40EXAMPLE.COM", 200, [:]
        ) { "[]" }
      ], scope: .test))
  func iLikeFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .ilike("email", pattern: "%@EXAMPLE.COM")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=%2A&deleted_at=is.NULL", 200, [:]) {
          "[]"
        }

      ], scope: .test))
  func isFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .is("deleted_at", value: nil)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&status=in.%28active%2Cpending%29", 200,
          [:]
        ) { "[]" }
      ], scope: .test))
  func inFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .in("status", values: ["active", "pending"])
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&tags=in.%28%22a%2Cb%22%2C%22c%28d%29%22%2Cplain%29",
          200, [:]
        ) { "[]" }
      ], scope: .test))
  func inFilterQuotesValuesWithReservedCharacters() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .in("tags", values: ["a,b", "c(d)", "plain"])
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&roles=cd.%7Badmin%2Cuser%7D", 200, [:]
        ) { "[]" }
      ], scope: .test))
  func containedByFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .containedBy("roles", value: ["admin", "user"])
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&age_range=sl.%5B18%2C25%29&other_range=sr.%5B25%2C35%29&third_range=nxl.%5B35%2C45%29&fourth_range=nxr.%5B45%2C55%29&fifth_range=adj.%5B55%2C65%29",
          200, [:]
        ) { "[]" }
      ], scope: .test))
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

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&schedule=ov.%7B9%3A00%2C17%3A00%7D",
          200, [:]
        ) { "[]" }
      ], scope: .test))
  func overlapsFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .overlaps("schedule", value: ["9:00", "17:00"])
      .execute()
  }

  // `match(_:)` iterates a `[String: any PostgrestFilterValue]`, so `status`/`role` query item
  // order is not deterministic across process launches (Swift's dictionary hash seed is
  // randomized per run). Match on `.query` (order-insensitive) instead of the default `.url`
  // matcher so this test isn't flaky while still verifying both filters are present and correct.
  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&status=eq.active&role=eq.admin", 200,
          [:]
        ) { "[]" }
      ], matching: [.method, .path, .query], scope: .test))
  func matchFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .match(["status": "active", "role": "admin"])
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=%2A&created_at=gt.2023-01-01", 200, [:]) {
          "[]"
        }
      ], scope: .test))
  func filterEscapeHatch() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .filter("created_at", operator: "gt", value: "2023-01-01")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=%2A&status=neq.inactive", 200, [:]) {
          "[]"
        }

      ], scope: .test))
  func neqFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .neq("status", value: "inactive")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=%2A&age=gt.21", 200, [:]) { "[]" }
      ], scope: .test))
  func gtFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .gt("age", value: 21)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=%2A&age=lt.65", 200, [:]) { "[]" }
      ], scope: .test))
  func ltFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .lt("age", value: 65)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=%2A&age=lte.65", 200, [:]) { "[]" }
      ], scope: .test))
  func lteFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .lte("age", value: 65)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&name=like%28all%29.%7B%25test%25%2C%25user%25%7D",
          200, [:]
        ) { "[]" }
      ], scope: .test))
  func likeAllOfFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .likeAllOf("name", patterns: ["%test%", "%user%"])
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&name=like%28any%29.%7B%25test%25%2C%25user%25%7D",
          200, [:]
        ) { "[]" }
      ], scope: .test))
  func likeAnyOfFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .likeAnyOf("name", patterns: ["%test%", "%user%"])
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&name=ilike%28all%29.%7B%25TEST%25%2C%25USER%25%7D",
          200, [:]
        ) { "[]" }
      ], scope: .test))
  func iLikeAllOfFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .iLikeAllOf("name", patterns: ["%TEST%", "%USER%"])
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&name=ilike%28any%29.%7B%25TEST%25%2C%25USER%25%7D",
          200, [:]
        ) { "[]" }
      ], scope: .test))
  func iLikeAnyOfFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .iLikeAnyOf("name", patterns: ["%TEST%", "%USER%"])
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=%2A&description=fts.programmer", 200, [:])
        { "[]" }
      ], scope: .test))
  func ftsFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .fts("description", query: "programmer")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/users?select=%2A&email=match.%5E.%2B%40.%2B%5C..%2B%24",
          200, [:]
        ) { "[]" }
      ], scope: .test))
  func regexMatchFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .match("email", pattern: "^.+@.+\\..+$")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=%2A&name=imatch.%5Ejohn", 200, [:]) {
          "[]"
        }

      ], scope: .test))
  func regexImatchFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .imatch("name", pattern: "^john")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users?select=%2A&status=isdistinct.null", 200, [:]) {
          "[]"
        }
      ], scope: .test))
  func isDistinctFilter() async throws {
    _ =
      try await sut
      .from("users")
      .select()
      .isDistinct("status", value: "null")
      .execute()
  }
}
