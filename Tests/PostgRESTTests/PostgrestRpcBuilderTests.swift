//
//  PostgrestRpcBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Foundation
import PostgREST
import Replay
import Testing

@Suite
struct PostgrestRpcBuilderTests {
  let fixture = PostgrestQueryFixture()
  var url: URL { fixture.url }
  var sut: PostgrestClient { fixture.sut }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/rest/v1/rpc/list_stored_countries", 200,
          [:],
          {
            """
            {
              "id": 1,
              "name": "France"
            }
            """
          })
      ], matching: [.method, .path], scope: .test))
  func rpc() async throws {
    let country =
      try await sut
      .rpc("list_stored_countries")
      .eq("id", value: 1)
      .single()
      .execute()
      .value as JSONObject

    #expect(country["name"]?.stringValue == "France")
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/rpc/hello_world", 200, [:]) { "Hello World" }
      ], matching: [.method, .path], scope: .test))
  func rpcReadOnly() async throws {
    try await sut
      .rpc("hello_world", get: true)
      .execute()
  }

  @Test
  func rpcWithGetMethodAndNonJSONObjectShouldThrowError() async throws {
    do {
      try await sut
        .rpc("hello", params: [1, 2, 3], get: true)
        .execute()
    } catch let error as PostgrestError {
      #expect(
        error.message == "Params should be a key-value type when using `GET` or `HEAD` options.")
    }
  }

  @Test
  func rpcWithHeadMethodAndNonJSONObjectShouldThrowError() async throws {
    do {
      try await sut
        .rpc("hello", params: [1, 2, 3], head: true)
        .execute()
    } catch let error as PostgrestError {
      #expect(
        error.message == "Params should be a key-value type when using `GET` or `HEAD` options.")
    }
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/rpc/sum", 200,
          [:],
          {
            """
            {
              "sum": 6
            }
            """
          })
      ], matching: [.method, .path], scope: .test))
  func rpcWithGetMethodAndJSONObjectShouldCleanArray() async throws {
    struct Response: Decodable {
      let sum: Int
    }

    let response =
      try await sut
      .rpc(
        "sum",
        params: [
          "numbers": [1, 2, 3],
          "key": "value",
        ] as JSONObject,
        get: true
      )
      .execute()
      .value as Response

    #expect(response.sum == 6)
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/rpc/scalar", 200, [:]) { "{}" }
      ], matching: [.method, .path], scope: .test))
  func rpcWithGetMethodEncodesScalarParamsByJSONType() async throws {
    try await sut
      .rpc(
        "scalar",
        params: [
          "enabled": true,
          "disabled": false,
          "number": 42,
          "maybe": .null,
          "nested": ["a": 1],
          "flags": [true, false, .null],
        ] as JSONObject,
        get: true
      )
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/rest/v1/rpc/hello", 200, [:]) { "" }
      ], matching: [.method, .path], scope: .test))
  func rpcWithCount() async throws {
    try await sut.rpc("hello", count: .estimated).execute()
  }
}
