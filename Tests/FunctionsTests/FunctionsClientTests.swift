import ConcurrencyExtras
import Foundation
import HTTPTypes
import Replay
import Testing

@testable import Functions

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct FunctionsClientTests {
  let url = URL(string: "http://localhost:5432/functions/v1")!
  let apiKey =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

  func makeSUT(region: String? = nil) -> FunctionsClient {
    FunctionsClient(
      url: url,
      headers: [
        "apikey": apiKey
      ],
      region: region,
      fetch: { try await Replay.session.data(for: $0) }
    )
  }

  @Test
  func initTest() async {
    let client = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      region: .saEast1
    )
    #expect(client.region == "sa-east-1")

    #expect(client.headers[.init("apikey")!] == apiKey)
    #expect(client.headers[.init("X-Client-Info")!] != nil)
  }

  @Test
  func initWithCustomDecoder() async {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase

    let client = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      decoder: decoder
    )

    #expect(client.decoder === decoder)
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, URL(string: "http://localhost:5432/functions/v1/hello_world")!, body: "")
      ], scope: .test))
  func invoke() async throws {
    let sut = makeSUT()

    try await sut.invoke(
      "hello_world",
      options: .init(headers: ["X-Custom-Key": "value"], body: ["name": "Supabase"])
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, URL(string: "http://localhost:5432/functions/v1/hello")!,
          body: #"{"message":"Hello, world!","status":"ok"}"#)
      ], scope: .test))
  func invokeReturningDecodable() async throws {
    let sut = makeSUT()

    struct Payload: Decodable {
      var message: String
      var status: String
    }

    let response = try await sut.invoke("hello") as Payload
    #expect(response.message == "Hello, world!")
    #expect(response.status == "ok")
  }

  @Test(
    .replay(
      stubs: [
        Stub(.delete, URL(string: "http://localhost:5432/functions/v1/hello-world")!, body: "")
      ], scope: .test))
  func invokeWithCustomMethod() async throws {
    let sut = makeSUT()

    try await sut.invoke("hello-world", options: .init(method: .delete))
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, URL(string: "http://localhost:5432/functions/v1/hello-world")!, body: "")
      ],
      matching: [.method, .path],
      scope: .test
    ))
  func invokeWithQuery() async throws {
    let sut = makeSUT()

    try await sut.invoke(
      "hello-world",
      options: .init(
        query: [URLQueryItem(name: "key", value: "value")]
      )
    )
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, URL(string: "http://localhost:5432/functions/v1/hello-world")!, body: "")
      ],
      matching: [.method, .path],
      scope: .test
    ))
  func invokeWithRegionDefinedInClient() async throws {
    let sut = makeSUT(region: FunctionRegion.caCentral1.rawValue)

    try await sut.invoke("hello-world")
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, URL(string: "http://localhost:5432/functions/v1/hello-world")!, body: "")
      ],
      matching: [.method, .path],
      scope: .test
    ))
  func invokeWithRegion() async throws {
    let sut = makeSUT()

    try await sut.invoke("hello-world", options: .init(region: .caCentral1))
  }

  @Test(
    .replay(
      stubs: [
        Stub(.post, URL(string: "http://localhost:5432/functions/v1/hello-world")!, body: "")
      ], scope: .test))
  func invokeWithoutRegion() async throws {
    let sut = makeSUT(region: nil)

    try await sut.invoke("hello-world")
  }

  @Test
  func invoke_shouldThrow_URLError_badServerResponse() async {
    let sut = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      fetch: { _ in throw URLError(.badServerResponse) }
    )

    do {
      try await sut.invoke("hello_world")
      Issue.record("Invoke should fail.")
    } catch let urlError as URLError {
      #expect(urlError.code == .badServerResponse)
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, URL(string: "http://localhost:5432/functions/v1/hello_world")!, status: 300,
          body: "")
      ], scope: .test))
  func invoke_shouldThrow_FunctionsError_httpError() async {
    let sut = makeSUT()

    do {
      try await sut.invoke("hello_world")
      Issue.record("Invoke should fail.")
    } catch let FunctionsError.httpError(code, _) {
      #expect(code == 300)
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  @Test(
    .replay(
      stubs: [
        Stub(
          .post, URL(string: "http://localhost:5432/functions/v1/hello_world")!,
          headers: ["x-relay-error": "true"], body: "")
      ], scope: .test))
  func invoke_shouldThrow_FunctionsError_relayError() async {
    let sut = makeSUT()

    do {
      try await sut.invoke("hello_world")
      Issue.record("Invoke should fail.")
    } catch FunctionsError.relayError {
    } catch {
      Issue.record("Unexpected error thrown \(error)")
    }
  }

  @Test
  func setAuth() {
    let sut = makeSUT()

    sut.setAuth(token: "access.token")
    #expect(sut.headers[.authorization] == "Bearer access.token")

    sut.setAuth(token: nil)
    #expect(sut.headers[.authorization] == nil)
  }

  @Test(
    .replay(stubs: [
      Stub(.post, URL(string: "http://localhost:5432/functions/v1/stream")!, body: "hello world")
    ]))
  func invokeWithStreamedResponse() async throws {
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    Replay.configure(sessionConfiguration)

    let sut = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      sessionConfiguration: sessionConfiguration
    )

    let stream = sut._invokeWithStreamedResponse("stream")

    for try await value in stream {
      #expect(String(decoding: value, as: UTF8.self) == "hello world")
    }
  }

  @Test(
    .replay(stubs: [
      Stub(.post, URL(string: "http://localhost:5432/functions/v1/stream")!, status: 300, body: "")
    ]))
  func invokeWithStreamedResponseHTTPError() async throws {
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    Replay.configure(sessionConfiguration)

    let sut = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      sessionConfiguration: sessionConfiguration
    )

    let stream = sut._invokeWithStreamedResponse("stream")

    do {
      for try await _ in stream {
        Issue.record("should throw error")
      }
    } catch let FunctionsError.httpError(code, _) {
      #expect(code == 300)
    }
  }

  @Test(
    .replay(stubs: [
      Stub(
        .post, URL(string: "http://localhost:5432/functions/v1/stream")!,
        headers: ["x-relay-error": "true"], body: "")
    ]))
  func invokeWithStreamedResponseRelayError() async throws {
    let sessionConfiguration = URLSessionConfiguration.ephemeral
    Replay.configure(sessionConfiguration)

    let sut = FunctionsClient(
      url: url,
      headers: ["apikey": apiKey],
      sessionConfiguration: sessionConfiguration
    )

    let stream = sut._invokeWithStreamedResponse("stream")

    do {
      for try await _ in stream {
        Issue.record("should throw error")
      }
    } catch FunctionsError.relayError {
    }
  }
}
