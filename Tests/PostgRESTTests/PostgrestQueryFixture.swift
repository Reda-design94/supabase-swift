//
//  PostgrestQueryFixture.swift
//  Supabase
//
//  Created by Guilherme Souza on 21/01/25.
//

import Foundation
import PostgREST
import Replay
import TestHelpers

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

/// Shared fixture for suites that exercise `PostgrestClient` against a mocked backend via Replay.
///
/// Suites compose this instead of subclassing, since Swift Testing suites don't share instance
/// state through inheritance. Each suite creates its own `PostgrestQueryFixture` in its `init()`.
struct PostgrestQueryFixture {
  static let url = URL(string: "http://localhost:54321/rest/v1")!

  var url: URL { Self.url }

  let sut: PostgrestClient

  init() {
    sut = PostgrestClient(
      url: Self.url,
      headers: [
        "apikey":
          "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
      ],
      logger: nil,
      fetch: { try await Replay.session.data(for: $0) },
      encoder: {
        let encoder = PostgrestClient.Configuration.jsonEncoder
        encoder.outputFormatting = [.sortedKeys]
        return encoder
      }()
    )
  }
}

struct User: Codable, Sendable {
  let id: Int
  let username: String
}

struct Country: Decodable {
  let name: String
  let cities: [City]

  struct City: Decodable {
    let name: String
  }
}
