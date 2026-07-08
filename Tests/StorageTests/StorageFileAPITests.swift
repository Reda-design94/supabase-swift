import ConcurrencyExtras
import Foundation
import Replay
import Testing

@testable import Storage

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct StorageFileAPITests {
  let url = URL(string: "http://localhost:54321/storage/v1")!

  init() {
    testingBoundary.setValue("alamofire.boundary.e56f43407f772505")

    JSONEncoder.defaultStorageEncoder.outputFormatting = [.sortedKeys]
    JSONEncoder.unconfiguredEncoder.outputFormatting = [.sortedKeys]
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
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/list/bucket",
          200,
          ["Content-Type": "application/json"],
          {
            """
            [
              {
                "name": "test.txt",
                "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "updatedAt": "2024-01-01T00:00:00Z",
                "createdAt": "2024-01-01T00:00:00Z",
                "lastAccessedAt": "2024-01-01T00:00:00Z",
                "metadata": {}
              }
            ]
            """
          }
        )
      ]
    )
  )
  func listFiles() async throws {
    let storage = makeSUT()
    let result = try await storage.from("bucket").list(path: "folder")
    #expect(result.count == 1)
    #expect(result[0].name == "test.txt")
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/list/bucket",
          200,
          ["Content-Type": "application/json"],
          { "[]" }
        )
      ]
    )
  )
  func listFilesWithPartialSortByColumn() async throws {
    let storage = makeSUT()
    _ = try await storage.from("bucket").list(
      path: "folder",
      options: SearchOptions(sortBy: SortBy(column: "updated_at"))
    )
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/list/bucket",
          200,
          ["Content-Type": "application/json"],
          { "[]" }
        )
      ]
    )
  )
  func listFilesWithPartialSortByOrder() async throws {
    let storage = makeSUT()
    _ = try await storage.from("bucket").list(
      path: "folder",
      options: SearchOptions(sortBy: SortBy(order: .descending))
    )
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/list/bucket",
          200,
          ["Content-Type": "application/json"],
          { "[]" }
        )
      ]
    )
  )
  func listFilesWithFullSortByOverride() async throws {
    let storage = makeSUT()
    _ = try await storage.from("bucket").list(
      path: "folder",
      options: SearchOptions(sortBy: SortBy(column: "updated_at", order: .descending))
    )
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/list/bucket",
          200,
          ["Content-Type": "application/json"],
          { "[]" }
        )
      ]
    )
  )
  func listFilesPreservesDefaultLimitWhenOnlyOffsetProvided() async throws {
    let storage = makeSUT()
    _ = try await storage.from("bucket").list(
      path: "folder",
      options: SearchOptions(offset: 10, sortBy: SortBy(column: "name", order: .ascending))
    )
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/list/bucket",
          200,
          ["Content-Type": "application/json"],
          { "[]" }
        )
      ]
    )
  )
  func listFilesPreservesDefaultOffsetWhenOnlyLimitProvided() async throws {
    let storage = makeSUT()
    _ = try await storage.from("bucket").list(
      path: "folder",
      options: SearchOptions(limit: 50, sortBy: SortBy(column: "name", order: .ascending))
    )
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/list/bucket",
          200,
          ["Content-Type": "application/json"],
          { "[]" }
        )
      ]
    )
  )
  func listFilesWithExplicitZeroLimitIsNotTreatedAsMissing() async throws {
    let storage = makeSUT()
    _ = try await storage.from("bucket").list(
      path: "folder",
      options: SearchOptions(
        limit: 0, offset: 5, sortBy: SortBy(column: "name", order: .ascending))
    )
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/move",
          200,
          [:],
          { "" }
        )
      ],
      matching: [
        .method, .path,
        .custom { request, _ in
          jsonBody(of: request) == [
            "bucketId": "bucket",
            "sourceKey": "old/path.txt",
            "destinationKey": "new/path.txt",
            "destinationBucket": nil,
          ]
        },
      ]
    )
  )
  func move() async throws {
    let storage = makeSUT()
    try await storage.from("bucket").move(
      from: "old/path.txt",
      to: "new/path.txt"
    )
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/copy",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "Key": "object/dest/file.txt"
            }
            """
          }
        )
      ],
      matching: [
        .method, .path,
        .custom { request, _ in
          jsonBody(of: request) == [
            "bucketId": "bucket",
            "sourceKey": "source/file.txt",
            "destinationKey": "dest/file.txt",
            "destinationBucket": nil,
          ]
        },
      ]
    )
  )
  func copy() async throws {
    let storage = makeSUT()
    let key = try await storage.from("bucket").copy(
      from: "source/file.txt",
      to: "dest/file.txt"
    )

    #expect(key == "object/dest/file.txt")
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/sign/bucket/file.txt",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
            }
            """
          }
        )
      ]
    )
  )
  func createSignedURL() async throws {
    let storage = makeSUT()
    let url = try await storage.from("bucket").createSignedURL(
      path: "file.txt",
      expiresIn: 3600
    )
    #expect(
      url.absoluteString == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi")
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/sign/bucket/file.txt",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
            }
            """
          }
        )
      ]
    )
  )
  func createSignedURL_download() async throws {
    let storage = makeSUT()
    let url = try await storage.from("bucket").createSignedURL(
      path: "file.txt",
      expiresIn: 3600,
      download: true
    )
    #expect(
      url.absoluteString
        == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&download=")
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/sign/bucket",
          200,
          ["Content-Type": "application/json"],
          {
            """
            [
              {
                "path": "file.txt",
                "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
              },
              {
                "path": "file2.txt",
                "signedURL": "object/upload/sign/bucket/file2.txt?token=abc.def.ghi"
              }
            ]
            """
          }
        )
      ]
    )
  )
  func createSignedURLs() async throws {
    let storage = makeSUT()
    let paths = ["file.txt", "file2.txt"]
    let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
      paths: paths,
      expiresIn: 3600
    )
    #expect(results.count == 2)
    guard case .success(let path0, let url0) = results[0] else {
      Issue.record("Expected success for file.txt")
      return
    }
    #expect(path0 == "file.txt")
    #expect(
      url0.absoluteString == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi")
    guard case .success(let path1, let url1) = results[1] else {
      Issue.record("Expected success for file2.txt")
      return
    }
    #expect(path1 == "file2.txt")
    #expect(
      url1.absoluteString == "\(self.url)/object/upload/sign/bucket/file2.txt?token=abc.def.ghi")
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/sign/bucket",
          200,
          ["Content-Type": "application/json"],
          {
            """
            [
              {
                "path": "file.txt",
                "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
              },
              {
                "path": "file2.txt",
                "signedURL": "object/upload/sign/bucket/file2.txt?token=abc.def.ghi"
              }
            ]
            """
          }
        )
      ]
    )
  )
  func createSignedURLs_download() async throws {
    let storage = makeSUT()
    let paths = ["file.txt", "file2.txt"]
    let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
      paths: paths,
      expiresIn: 3600,
      download: true
    )
    #expect(results.count == 2)
    guard case .success(_, let url0) = results[0] else {
      Issue.record("Expected success for file.txt")
      return
    }
    #expect(
      url0.absoluteString
        == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&download=")
    guard case .success(_, let url1) = results[1] else {
      Issue.record("Expected success for file2.txt")
      return
    }
    #expect(
      url1.absoluteString
        == "\(self.url)/object/upload/sign/bucket/file2.txt?token=abc.def.ghi&download=")
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/sign/bucket",
          200,
          ["Content-Type": "application/json"],
          {
            """
            [
              {
                "path": "file.txt",
                "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
              },
              {
                "path": "missing.txt",
                "signedURL": null,
                "error": "Either the object does not exist or you do not have access to it"
              }
            ]
            """
          }
        )
      ]
    )
  )
  func createSignedURLs_withNullSignedURL() async throws {
    let storage = makeSUT()
    let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
      paths: ["file.txt", "missing.txt"],
      expiresIn: 3600
    )
    #expect(results.count == 2)
    guard case .success(let path0, _) = results[0] else {
      Issue.record("Expected success for file.txt")
      return
    }
    #expect(path0 == "file.txt")
    guard case .failure(let path1, let error1) = results[1] else {
      Issue.record("Expected failure for missing.txt")
      return
    }
    #expect(path1 == "missing.txt")
    #expect(error1 == "Either the object does not exist or you do not have access to it")
  }

  @Test(
    .replay(
      stubs: [
        .delete(
          "http://localhost:54321/storage/v1/object/bucket",
          204,
          ["Content-Type": "application/json"],
          {
            """
            [
              {
                "name": "file1.txt",
                "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                "updatedAt": "2024-01-01T00:00:00Z",
                "createdAt": "2024-01-01T00:00:00Z",
                "lastAccessedAt": "2024-01-01T00:00:00Z",
                "metadata": {}
              },
              {
                "name": "file2.txt",
                "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E00",
                "updatedAt": "2024-01-01T00:00:00Z",
                "createdAt": "2024-01-01T00:00:00Z",
                "lastAccessedAt": "2024-01-01T00:00:00Z",
                "metadata": {}
              }
            ]
            """
          }
        )
      ],
      matching: [
        .method, .path,
        .custom { request, _ in
          jsonBody(of: request) == ["prefixes": ["file1.txt", "file2.txt"]]
        },
      ]
    )
  )
  func remove() async throws {
    let storage = makeSUT()
    let objects = try await storage.from("bucket").remove(
      paths: ["file1.txt", "file2.txt"]
    )

    #expect(objects[0].name == "file1.txt")
    #expect(objects[1].name == "file2.txt")
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/move",
          400,
          ["Content-Type": "application/json"],
          {
            """
            {
              "message":"Error"
            }
            """
          }
        )
      ]
    )
  )
  func nonSuccessStatusCode() async throws {
    let storage = makeSUT()
    do {
      try await storage.from("bucket")
        .move(from: "source", to: "destination")
      Issue.record("Expected move to throw")
    } catch let error as StorageError {
      #expect(error.message == "Error")
    }
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/move",
          412,
          [:],
          { "error" }
        )
      ]
    )
  )
  func nonSuccessStatusCodeWithNonJSONResponse() async throws {
    let storage = makeSUT()
    do {
      try await storage.from("bucket")
        .move(from: "source", to: "destination")
      Issue.record("Expected move to throw")
    } catch let error as HTTPError {
      #expect(error.data == Data("error".utf8))
      #expect(error.response.statusCode == 412)
    }
  }

  @Test(
    .replay(
      stubs: [
        .put(
          "http://localhost:54321/storage/v1/object/bucket/file.txt",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "Id": "123",
              "Key": "bucket/file.txt"
            }
            """
          }
        )
      ]
    )
  )
  func updateFromData() async throws {
    let storage = makeSUT()
    let response = try await storage.from("bucket")
      .update(
        "file.txt",
        data: Data("hello world".utf8),
        options: FileOptions(
          metadata: [
            "mode": "test"
          ]
        )
      )

    #expect(response.id == "123")
    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test(
    .replay(
      stubs: [
        .put(
          "http://localhost:54321/storage/v1/object/bucket/file.txt",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "Id": "123",
              "Key": "bucket/file.txt"
            }
            """
          }
        )
      ]
    )
  )
  func updateFromURL() async throws {
    let storage = makeSUT()
    let response = try await storage.from("bucket")
      .update(
        "file.txt",
        fileURL: Bundle.module.url(forResource: "file", withExtension: "txt")!,
        options: FileOptions(
          metadata: [
            "mode": "test"
          ]
        )
      )

    #expect(response.id == "123")
    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/storage/v1/object/bucket/file.txt",
          200,
          [:],
          { "hello world" }
        )
      ]
    )
  )
  func download() async throws {
    let storage = makeSUT()
    let data = try await storage.from("bucket")
      .download(path: "file.txt")

    #expect(data == Data("hello world".utf8))
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/storage/v1/object/bucket/file.txt?version=1",
          200,
          [:],
          { "hello world" }
        )
      ],
      matching: [.method, .path]
    )
  )
  func downloadWithAdditionalQuery() async throws {
    let storage = makeSUT()
    let data = try await storage.from("bucket")
      .download(
        path: "file.txt",
        query: [URLQueryItem(name: "version", value: "1")]
      )

    #expect(data == Data("hello world".utf8))
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/storage/v1/object/bucket/file.txt",
          200,
          [:],
          { "hello world" }
        )
      ]
    )
  )
  func download_withEmptyTransformOptions() async throws {
    let storage = makeSUT()
    let data = try await storage.from("bucket")
      .download(path: "file.txt", options: TransformOptions())

    #expect(data == Data("hello world".utf8))
  }

  @Test
  func getPublicURL_withEmptyTransformOptions() throws {
    let storage = makeSUT()
    let publicURL = try storage.from("bucket")
      .getPublicURL(path: "image.png", options: TransformOptions())

    #expect(
      publicURL.absoluteString.contains("/object/public/"),
      "Empty transform should use /object/public/ path, got: \(publicURL.absoluteString)"
    )
    #expect(
      !publicURL.absoluteString.contains("/render/image/"),
      "Empty transform should not use /render/image/ path, got: \(publicURL.absoluteString)"
    )
  }

  @Test
  func getPublicURL_withActualTransformOptions() throws {
    let storage = makeSUT()
    let publicURL = try storage.from("bucket")
      .getPublicURL(path: "image.png", options: TransformOptions(width: 200))

    #expect(
      publicURL.absoluteString.contains("/render/image/"),
      "Non-empty transform should use /render/image/ path, got: \(publicURL.absoluteString)"
    )
  }

  static let sadcatData = try! Data(
    contentsOf: Bundle.module.url(forResource: "sadcat", withExtension: "jpg")!)

  @Test(
    .replay(
      stubs: [
        Stub(
          .get,
          "http://localhost:54321/storage/v1/render/image/authenticated/bucket/sadcat.txt?format=cover",
          status: 200,
          headers: ["Content-Type": "image/jpeg"],
          body: sadcatData
        )
      ],
      matching: [.method, .path]
    )
  )
  func download_withOptions() async throws {
    let storage = makeSUT()
    let data = try await storage.from("bucket")
      .download(
        path: "sadcat.txt",
        options: TransformOptions(format: "cover")
      )

    #expect(data == Self.sadcatData)
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/storage/v1/object/info/bucket/file.txt",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "name": "file.txt",
              "id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
              "version": "2"
            }
            """
          }
        )
      ]
    )
  )
  func info() async throws {
    let storage = makeSUT()
    let info = try await storage.from("bucket").info(path: "file.txt")

    #expect(info.name == "file.txt")
  }

  @Test(
    .replay(
      stubs: [
        .head(
          "http://localhost:54321/storage/v1/object/bucket/file.txt",
          200,
          [:]
        )
      ]
    )
  )
  func exists() async throws {
    let storage = makeSUT()
    let exists = try await storage.from("bucket").exists(path: "file.txt")

    #expect(exists)
  }

  @Test(
    .replay(
      stubs: [
        .head(
          "http://localhost:54321/storage/v1/object/bucket/file.txt",
          400,
          [:]
        )
      ]
    )
  )
  func exists_400_error() async throws {
    let storage = makeSUT()
    let exists = try await storage.from("bucket").exists(path: "file.txt")

    #expect(!exists)
  }

  @Test(
    .replay(
      stubs: [
        .head(
          "http://localhost:54321/storage/v1/object/bucket/file.txt",
          404,
          [:]
        )
      ]
    )
  )
  func exists_404_error() async throws {
    let storage = makeSUT()
    let exists = try await storage.from("bucket").exists(path: "file.txt")

    #expect(!exists)
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "url": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
            }
            """
          }
        )
      ]
    )
  )
  func createSignedUploadURL() async throws {
    let storage = makeSUT()
    let response = try await storage.from("bucket")
      .createSignedUploadURL(path: "file.txt")

    #expect(response.path == "file.txt")
    #expect(response.token == "abc.def.ghi")
    #expect(
      response.signedURL.absoluteString
        == "http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
    )
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "url": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
            }
            """
          }
        )
      ]
    )
  )
  func createSignedUploadURL_withUpsert() async throws {
    let storage = makeSUT()
    let response = try await storage.from("bucket")
      .createSignedUploadURL(
        path: "file.txt",
        options: CreateSignedUploadURLOptions(
          upsert: true
        )
      )

    #expect(response.path == "file.txt")
    #expect(response.token == "abc.def.ghi")
    #expect(
      response.signedURL.absoluteString
        == "http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi"
    )
  }

  @Test(
    .replay(
      stubs: [
        .put(
          "http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "Key": "bucket/file.txt"
            }
            """
          }
        )
      ],
      matching: [.method, .path]
    )
  )
  func uploadToSignedURL() async throws {
    let storage = makeSUT()
    let response = try await storage.from("bucket")
      .uploadToSignedURL("file.txt", token: "abc.def.ghi", data: Data("hello world".utf8))

    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test(
    .replay(
      stubs: [
        .put(
          "http://localhost:54321/storage/v1/object/upload/sign/bucket/file.txt?token=abc.def.ghi",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "Key": "bucket/file.txt"
            }
            """
          }
        )
      ],
      matching: [.method, .path]
    )
  )
  func uploadToSignedURL_fromFileURL() async throws {
    let storage = makeSUT()
    let response = try await storage.from("bucket")
      .uploadToSignedURL(
        "file.txt",
        token: "abc.def.ghi",
        fileURL: Bundle.module.url(forResource: "file", withExtension: "txt")!,
        options: FileOptions(
          headers: ["X-Mode": "test"]
        )
      )

    #expect(response.path == "file.txt")
    #expect(response.fullPath == "bucket/file.txt")
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/sign/bucket/file.txt",
          200,
          ["Content-Type": "application/json"],
          {
            """
            {
              "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
            }
            """
          }
        )
      ]
    )
  )
  func createSignedURL_cacheNonce() async throws {
    let storage = makeSUT()
    let url = try await storage.from("bucket").createSignedURL(
      path: "file.txt",
      expiresIn: 3600,
      cacheNonce: "abc123"
    )
    #expect(
      url.absoluteString
        == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&cacheNonce=abc123")
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/storage/v1/object/sign/bucket",
          200,
          ["Content-Type": "application/json"],
          {
            """
            [
              {
                "path": "file.txt",
                "signedURL": "object/upload/sign/bucket/file.txt?token=abc.def.ghi"
              }
            ]
            """
          }
        )
      ]
    )
  )
  func createSignedURLs_cacheNonce() async throws {
    let storage = makeSUT()
    let results: [SignedURLResult] = try await storage.from("bucket").createSignedURLs(
      paths: ["file.txt"],
      expiresIn: 3600,
      cacheNonce: "abc123"
    )
    guard case .success(_, let url) = results[0] else {
      Issue.record("Expected success for file.txt")
      return
    }
    #expect(
      url.absoluteString
        == "\(self.url)/object/upload/sign/bucket/file.txt?token=abc.def.ghi&cacheNonce=abc123")
  }

  @Test
  func getPublicURL_cacheNonce() throws {
    let storage = makeSUT()
    let url = try storage.from("bucket").getPublicURL(
      path: "file.txt",
      cacheNonce: "abc123"
    )
    #expect(
      url.absoluteString
        == "\(self.url)/object/public/bucket/file.txt?cacheNonce=abc123")
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/storage/v1/object/bucket/file.txt?cacheNonce=abc123",
          200,
          [:],
          { "hello world" }
        )
      ],
      matching: [.method, .path]
    )
  )
  func download_cacheNonce() async throws {
    let storage = makeSUT()
    let data = try await storage.from("bucket")
      .download(path: "file.txt", cacheNonce: "abc123")

    #expect(data == Data("hello world".utf8))
  }
}

/// Decodes a request's JSON body for structural comparison in `.custom` Replay matchers,
/// so write-endpoint tests can assert on request-body content (e.g. `sourceKey`/`destinationKey`
/// are not swapped) without needing exact byte-for-byte matching (key order, whitespace).
///
/// `URLSession` may expose the body via `httpBody` or, once the request has been handed to the
/// loading system, via `httpBodyStream` — read whichever is present.
private func jsonBody(of request: URLRequest) -> [String: AnyJSON]? {
  let data: Data?
  if let body = request.httpBody {
    data = body
  } else if let stream = request.httpBodyStream {
    data = Data(readingAllOf: stream)
  } else {
    data = nil
  }
  guard let data else { return nil }
  return try? JSONDecoder().decode([String: AnyJSON].self, from: data)
}

extension Data {
  fileprivate init(readingAllOf stream: InputStream) {
    stream.open()
    defer { stream.close() }
    var data = Data()
    let bufferSize = 4096
    var buffer = [UInt8](repeating: 0, count: bufferSize)
    while stream.hasBytesAvailable {
      let read = stream.read(&buffer, maxLength: bufferSize)
      if read > 0 {
        data.append(buffer, count: read)
      } else {
        break
      }
    }
    self = data
  }
}
