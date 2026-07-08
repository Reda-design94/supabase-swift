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
          "http://localhost:54321/rest/v1/users", 200,
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
      ], matching: [.method, .path], scope: .test))
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
        .get("http://localhost:54321/rest/v1/users", 200, [:]) { "" }
      ], matching: [.method, .path], scope: .test))
  func selectWithWhitespaceInQuery() async throws {
    try await sut
      .from("users")
      .select("some column")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users", 200, [:]) { "" }
      ], matching: [.method, .path], scope: .test))
  func selectWithQuoteInQuery() async throws {
    try await sut
      .from("users")
      .select(#"some "column""#)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .head("http://localhost:54321/rest/v1/users", 200, ["Content-Range": "0-9/10"])
      ], matching: [.method, .path], scope: .test))
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
        .post("http://localhost:54321/rest/v1/users", 201, [:]) { "" }
      ], matching: [.method, .path], scope: .test))
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
        .post("http://localhost:54321/rest/v1/users", 201, [:]) { "" }
      ], matching: [.method, .path], scope: .test))
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
      ], matching: [.method, .path], scope: .test))
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
        .patch("http://localhost:54321/rest/v1/users", 201, [:]) { "" }
      ], matching: [.method, .path], scope: .test))
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
        .post("http://localhost:54321/rest/v1/users", 201, [:]) { "" }
      ], matching: [.method, .path], scope: .test))
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
      ], matching: [.method, .path], scope: .test))
  func upsertIgnoreDuplicates() async throws {
    try await sut
      .from("users")
      .upsert(User(id: 1, username: "admin"), ignoreDuplicates: true)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .delete("http://localhost:54321/rest/v1/users", 204, [:]) { "" }
      ], matching: [.method, .path], scope: .test))
  func delete() async throws {
    try await sut
      .from("users")
      .setHeader(name: "Prefer", value: "existing=value")
      .delete(count: .estimated)
      .eq("username", value: "supabase")
      .execute()
  }
}
