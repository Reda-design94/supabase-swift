import Foundation
import Replay
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct StorageBucketAPITests {
  let url = URL(string: "http://localhost:54321/storage/v1")!

  init() {
    JSONEncoder.defaultStorageEncoder.outputFormatting = [
      .sortedKeys
    ]
  }

  private func makeSUT() -> SupabaseStorageClient {
    SupabaseStorageClient(
      configuration: StorageClientConfiguration(
        url: url,
        headers: [
          "apikey":
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"
        ],
        session: StorageHTTPSession(
          fetch: { try await Replay.session.data(for: $0) },
          upload: { try await Replay.session.upload(for: $0, from: $1) }
        ),
        logger: nil
      )
    )
  }

  @Test(
    arguments: [
      (
        "https://blah.supabase.co/storage/v1",
        "https://blah.storage.supabase.co/storage/v1",
        "update legacy prod host to new host"
      ),
      (
        "https://blah.supabase.red/storage/v1",
        "https://blah.storage.supabase.red/storage/v1",
        "update legacy staging host to new host"
      ),
      (
        "https://blah.storage.supabase.co/storage/v1",
        "https://blah.storage.supabase.co/storage/v1",
        "accept new host without modification"
      ),
      (
        "https://blah.supabase.co.example.com/storage/v1",
        "https://blah.supabase.co.example.com/storage/v1",
        "not modify non-platform hosts"
      ),
      (
        "http://localhost:1234/storage/v1",
        "http://localhost:1234/storage/v1",
        "support local host with port without modification"
      ),
    ]
  )
  func urlConstructionWithNewHostname(input: String, expected: String, description: String) {
    let storage = SupabaseStorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: input)!,
        headers: [:],
        useNewHostname: true
      )
    )
    #expect(
      storage.configuration.url.absoluteString == expected,
      "should \(description) if useNewHostname is true"
    )
  }

  @Test(
    arguments: [
      "https://blah.supabase.co/storage/v1",
      "https://blah.supabase.red/storage/v1",
      "https://blah.storage.supabase.co/storage/v1",
      "https://blah.supabase.co.example.com/storage/v1",
      "http://localhost:1234/storage/v1",
    ]
  )
  func urlConstructionWithoutNewHostname(input: String) {
    let storage = SupabaseStorageClient(
      configuration: StorageClientConfiguration(
        url: URL(string: input)!,
        headers: [:],
        useNewHostname: false
      )
    )
    #expect(storage.configuration.url.absoluteString == input)
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/storage/v1/bucket/bucket123",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
                "id": "bucket123",
                "name": "test-bucket",
                "owner": "owner123",
                "public": false,
                "created_at": "2024-01-01T00:00:00.000Z",
                "updated_at": "2024-01-01T00:00:00.000Z"
            }
            """
          }
        )
      ]
    )
  )
  func getBucket() async throws {
    let storage = makeSUT()
    let bucket = try await storage.getBucket("bucket123")
    #expect(bucket.id == "bucket123")
    #expect(bucket.name == "test-bucket")
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/storage/v1/bucket",
          200,
          ["Content-Type": "application/json"],
          {
            """
            [
              {
                "id": "bucket123",
                "name": "test-bucket",
                "owner": "owner123",
                "public": false,
                "created_at": "2024-01-01T00:00:00.000Z",
                "updated_at": "2024-01-01T00:00:00.000Z"
              }
            ]
            """
          }
        )
      ]
    )
  )
  func listBuckets() async throws {
    let storage = makeSUT()
    let buckets = try await storage.listBuckets()
    #expect(buckets.count == 1)
    #expect(buckets[0].name == "test-bucket")
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/bucket",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "id": "newbucket",
              "name": "new-bucket",
              "owner": "owner123",
              "public": true,
              "created_at": "2024-01-01T00:00:00.000Z",
              "updated_at": "2024-01-01T00:00:00.000Z"
            }
            """
          }
        )
      ]
    )
  )
  func createBucket() async throws {
    let storage = makeSUT()
    let options = BucketOptions(public: true)
    try await storage.createBucket(
      "newbucket",
      options: options
    )
  }

  @Test(
    .replay(
      stubs: [
        .put(
          "http://localhost:54321/storage/v1/bucket/bucket123",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "id": "bucket123",
              "name": "updated-bucket",
              "owner": "owner123",
              "public": true,
              "created_at": "2024-01-01T00:00:00.000Z",
              "updated_at": "2024-01-01T00:00:00.000Z"
            }
            """
          }
        )
      ]
    )
  )
  func updateBucket() async throws {
    let storage = makeSUT()
    let options = BucketOptions(public: true)
    try await storage.updateBucket(
      "bucket123",
      options: options
    )
  }

  @Test(
    .replay(
      stubs: [
        .delete(
          "http://localhost:54321/storage/v1/bucket/bucket123",
          200,
          [:],
          { "" }
        )
      ]
    )
  )
  func deleteBucket() async throws {
    let storage = makeSUT()
    try await storage.deleteBucket("bucket123")
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/bucket/bucket123/empty",
          200,
          [:],
          { "" }
        )
      ]
    )
  )
  func emptyBucket() async throws {
    let storage = makeSUT()
    try await storage.emptyBucket("bucket123")
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/bucket",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "id": "newbucket",
              "name": "newbucket",
              "owner": "owner123",
              "public": false,
              "created_at": "2024-01-01T00:00:00.000Z",
              "updated_at": "2024-01-01T00:00:00.000Z"
            }
            """
          }
        )
      ]
    )
  )
  func createBucketWithFileSizeLimit() async throws {
    let storage = makeSUT()
    try await storage.createBucket(
      "newbucket",
      options: BucketOptions(isPublic: false, fileSizeLimit: 10_485_760)
    )
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/bucket",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "id": "newbucket",
              "name": "newbucket",
              "owner": "owner123",
              "public": false,
              "created_at": "2024-01-01T00:00:00.000Z",
              "updated_at": "2024-01-01T00:00:00.000Z"
            }
            """
          }
        )
      ]
    )
  )
  func createBucketWithHumanReadableFileSizeLimit() async throws {
    let storage = makeSUT()
    try await storage.createBucket(
      "newbucket",
      options: BucketOptions(isPublic: false, fileSizeLimit: "1mb")
    )
  }
}
