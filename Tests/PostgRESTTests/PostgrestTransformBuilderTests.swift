//
//  PostgrestTransformBuilderTests.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Foundation
import PostgREST
import Replay
import Testing

@Suite
struct PostgrestTransformBuilderTests {
  let fixture = PostgrestQueryFixture()
  var url: URL { fixture.url }
  var sut: PostgrestClient { fixture.sut }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/rest/v1/users", 201, [:]) { #"{"username":"admin""# }
      ], matching: [.method, .path], scope: .test))
  func select() async throws {
    try await sut
      .from("users")
      .insert(User(id: 1, username: "admin"), returning: .minimal)
      .select("username, \"first name\"")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/cities", 200,
          [:],
          {
            """
              [
                  {
                    "name": "United States",
                    "cities": [
                      {
                        "name": "New York City"
                      },
                      {
                        "name": "Atlanta"
                      }
                    ]
                  },
                  {
                    "name": "Vanuatu",
                    "cities": []
                  }
                ]
            """
          })
      ], matching: [.method, .path], scope: .test))
  func order() async throws {
    let countries =
      try await sut
      .from("cities")
      .select(
        """
        name,
        country:countries(
          name
        )
        """
      )
      .order("name", ascending: true, referencedTable: "countries")
      .execute()
      .value as [Country]

    #expect(countries[0].name == "United States")
    #expect(countries[0].cities[0].name == "New York City")
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/cities", 200, [:]) { "[]" }
      ], matching: [.method, .path], scope: .test))
  func multipleOrder() async throws {
    try await sut
      .from("cities")
      .select("name,num_of_habitants")
      .order("num_of_habitants")
      .order("name", ascending: false, nullsFirst: true)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/countries", 200,
          [:],
          {
            """
            [
              {
                "name": "United States",
                "cities": [
                  {
                    "name": "Atlanta"
                  }
                ]
              }
            ]
            """
          })
      ], matching: [.method, .path], scope: .test))
  func limit() async throws {
    let countries =
      try await sut
      .from("countries")
      .select(
        """
        name,
        cities (
          name
        )
        """
      )
      .limit(1, referencedTable: "cities")
      .execute()
      .value as [Country]

    #expect(countries[0].name == "United States")
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/countries", 200,
          [:],
          {
            """
            [
              {
                "name": "United States",
                "cities": [
                  {
                    "name": "Atlanta"
                  }
                ]
              }
            ]
            """
          })
      ], matching: [.method, .path], scope: .test))
  func range() async throws {
    let countries =
      try await sut
      .from("countries")
      .select(
        """
        name,
        cities (
          name
        )
        """
      )
      .range(from: 0, to: 1)
      .execute()
      .value as [Country]

    #expect(countries[0].name == "United States")
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/countries", 200, [:]) { "[]" }
      ], matching: [.method, .path], scope: .test))
  func rangeWithReferencedTable() async throws {
    try await sut
      .from("countries")
      .select(
        """
        name,
        cities (
          name
        )
        """
      )
      .range(from: 0, to: 1, referencedTable: "cities")
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/rest/v1/countries", 200,
          [:],
          {
            """
            {
              "name": "United States"
            }
            """
          })
      ], matching: [.method, .path], scope: .test))
  func single() async throws {
    let country =
      try await sut
      .from("countries")
      .select("name")
      .limit(1)
      .single()
      .execute()
      .value as [String: String]

    #expect(country["name"] == "United States")
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/countries", 200, [:]) {
          "id,name\n1,Afghanistan\n2,Albania\n3,Algeria"
        }
      ], matching: [.method, .path], scope: .test))
  func csv() async throws {
    let csv =
      try await sut
      .from("countries")
      .select()
      .csv()
      .execute()
      .string()

    let ids =
      csv?
      .split(separator: "\n")
      .dropFirst()
      .map { $0.split(separator: ",").first! } ?? []

    #expect(ids == ["1", "2", "3"])
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/countries", 200, [:]) { "[]" }
      ], matching: [.method, .path], scope: .test))
  func geoJSON() async throws {
    try await sut
      .from("countries")
      .select("area")
      .geojson()
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/countries", 200, [:]) {
          """
          Aggregate  (cost=33.34..33.36 rows=1 width=112) (actual time=0.041..0.041 rows=1 loops=1)
            Output: NULL::bigint, count(ROW(countries.id, countries.name)), COALESCE(json_agg(ROW(countries.id, countries.name)), '[]'::json), NULLIF(current_setting('response.headers'::text, true), ''::text), NULLIF(current_setting('response.status'::text, true), ''::text)
            ->  Limit  (cost=0.00..18.33 rows=1000 width=40) (actual time=0.005..0.006 rows=3 loops=1)
                  Output: countries.id, countries.name
                  ->  Seq Scan on public.countries  (cost=0.00..22.00 rows=1200 width=40) (actual time=0.004..0.005 rows=3 loops=1)
                        Output: countries.id, countries.name
          Query Identifier: -4730654291623321173
          Planning Time: 0.407 ms
          Execution Time: 0.119 ms
          """
        }
      ], matching: [.method, .path], scope: .test))
  func explain() async throws {
    let explain =
      try await sut
      .from("countries")
      .select()
      .explain(analyze: true, verbose: true)
      .execute()
      .string() ?? ""

    #expect(explain.contains("Aggregate"))
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/countries", 200, [:]) { "[]" }
      ], matching: [.method, .path], scope: .test))
  func explainWithJSONFormat() async throws {
    _ =
      try await sut
      .from("countries")
      .select()
      .explain(analyze: true, format: .json)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .patch("http://localhost:54321/rest/v1/users", 200, [:]) { "[]" }
      ], matching: [.method, .path], scope: .test))
  func maxAffectedOnUpdate() async throws {
    try await sut
      .from("users")
      .update(["username": "admin"])
      .eq("id", value: 1)
      .maxAffected(1)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .patch("http://localhost:54321/rest/v1/users", 200, [:]) { "[]" }
      ], matching: [.method, .path], scope: .test))
  func maxAffectedTwice() async throws {
    try await sut
      .from("users")
      .update(["username": "admin"])
      .eq("id", value: 1)
      .maxAffected(1)
      .maxAffected(5)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .delete("http://localhost:54321/rest/v1/users", 200, [:]) { "[]" }
      ], matching: [.method, .path], scope: .test))
  func maxAffectedOnDelete() async throws {
    try await sut
      .from("users")
      .delete()
      .in("id", values: [1, 2, 3, 4, 5])
      .maxAffected(5)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .post("http://localhost:54321/rest/v1/rpc/delete_users", 200, [:]) { "[]" }
      ], matching: [.method, .path], scope: .test))
  func maxAffectedOnRpc() async throws {
    try await sut
      .rpc("delete_users")
      .maxAffected(10)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/users", 200, [:]) { "[]" }
      ], matching: [.method, .path], scope: .test))
  func maxAffectedOnSelect() async throws {
    try await sut
      .from("users")
      .select()
      .maxAffected(3)
      .execute()
  }

  @Test(
    .replay(
      stubs: [
        .get("http://localhost:54321/rest/v1/countries", 200, [:]) { "[]" }
      ], matching: [.method, .path], scope: .test))
  func stripNulls() async throws {
    try await sut
      .from("countries")
      .select()
      .stripNulls()
      .execute()
  }

  @Test
  func stripNullsWithCSVThrowsError() async throws {
    do {
      try await sut
        .from("countries")
        .select()
        .csv()
        .stripNulls()
        .execute()
      Issue.record("Expected error to be thrown")
    } catch let error as PostgrestError {
      #expect(error.message == "`.stripNulls()` cannot be combined with `.csv()`")
    }
  }

  @Test
  func csvWithStripNullsThrowsError() async throws {
    do {
      try await sut
        .from("countries")
        .select()
        .stripNulls()
        .csv()
        .execute()
      Issue.record("Expected error to be thrown")
    } catch let error as PostgrestError {
      #expect(error.message == "`.csv()` cannot be combined with `.stripNulls()`")
    }
  }
}
