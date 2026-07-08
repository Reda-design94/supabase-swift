//
//  AuthAdminOAuthTests.swift
//
//
//  Created by Guilherme Souza on 02/10/25.
//

import ConcurrencyExtras
import CustomDump
import Foundation
import Replay
import TestHelpers
import Testing

@testable import Auth

#if canImport(FoundationNetworking)
  import FoundationNetworking
#endif

@Suite
struct AuthAdminOAuthTests {
  let clientId = UUID(uuidString: "E621E1F8-C36C-495A-93FC-0C247A3E6E5F")!
  let storage = InMemoryLocalStorage()

  private func makeSUT() -> AuthClient {
    let encoder = AuthClient.Configuration.jsonEncoder
    encoder.outputFormatting = [.sortedKeys]

    let configuration = AuthClient.Configuration(
      url: clientURL,
      headers: [
        "apikey": "supabase.publishable.key",
        "Authorization": "Bearer supabase.secret.key",
      ],
      localStorage: storage,
      logger: nil,
      encoder: encoder,
      fetch: { try await Replay.session.data(for: $0) }
    )

    return AuthClient(configuration: configuration)
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/auth/v1/admin/oauth/clients", 200,
          [
            "x-total-count": "1",
            "link": "<https://example.com?page=1>; rel=\"last\"",
          ],
          {
            """
            {
              "clients": [
                {
                  "client_id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
                  "client_name": "Test Client",
                  "client_type": "confidential",
                  "token_endpoint_auth_method": "client_secret_post",
                  "registration_type": "manual",
                  "redirect_uris": ["https://example.com/callback"],
                  "grant_types": ["authorization_code", "refresh_token"],
                  "response_types": ["code"],
                  "created_at": "2024-01-01T00:00:00.000Z",
                  "updated_at": "2024-01-01T00:00:00.000Z"
                }
              ],
              "aud": "authenticated"
            }
            """
          }
        )
      ], matching: [.method, .path], scope: .test
    )
  )
  func listOAuthClients() async throws {
    let sut = makeSUT()

    let response = try await sut.admin.oauth.listClients()

    #expect(response.clients.count == 1)
    #expect(response.clients[0].clientId == clientId)
    #expect(response.clients[0].clientName == "Test Client")
    #expect(response.aud == "authenticated")
    #expect(response.total == 1)
  }

  @Test(
    .replay(
      stubs: [
        .put(
          "http://localhost:54321/auth/v1/admin/oauth/clients/E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          200, [:],
          {
            """
            {
              "client_id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
              "client_name": "Update Client name",
              "client_secret": "secret123",
              "client_type": "confidential",
              "token_endpoint_auth_method": "client_secret_post",
              "registration_type": "manual",
              "redirect_uris": ["https://example.com/callback"],
              "grant_types": ["authorization_code", "refresh_token"],
              "response_types": ["code"],
              "created_at": "2024-01-01T00:00:00.000Z",
              "updated_at": "2024-01-01T00:00:00.000Z"
            }
            """
          }
        )
      ], matching: [.method, .path], scope: .test
    )
  )
  func updateOAuthClient() async throws {
    let sut = makeSUT()

    let client = try await sut.admin.oauth.updateClient(
      clientId: clientId,
      params: UpdateOAuthClientParams(
        clientName: "Update Client name",
        redirectUris: ["https://example.com/callback"],
        grantTypes: [.authorizationCode, .refreshToken]
      )
    )

    #expect(client.clientId == clientId)
    #expect(client.clientName == "Update Client name")
    #expect(client.clientSecret == "secret123")
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/auth/v1/admin/oauth/clients", 200, [:],
          {
            """
            {
              "client_id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
              "client_name": "New Client",
              "client_secret": "secret123",
              "client_type": "confidential",
              "token_endpoint_auth_method": "client_secret_post",
              "registration_type": "manual",
              "redirect_uris": ["https://example.com/callback"],
              "grant_types": ["authorization_code", "refresh_token"],
              "response_types": ["code"],
              "created_at": "2024-01-01T00:00:00.000Z",
              "updated_at": "2024-01-01T00:00:00.000Z"
            }
            """
          }
        )
      ], matching: [.method, .path], scope: .test
    )
  )
  func createOAuthClient() async throws {
    let sut = makeSUT()

    let params = CreateOAuthClientParams(
      clientName: "New Client",
      redirectUris: ["https://example.com/callback"]
    )

    let client = try await sut.admin.oauth.createClient(params: params)

    #expect(client.clientId == clientId)
    #expect(client.clientName == "New Client")
    #expect(client.clientSecret == "secret123")
  }

  @Test(
    .replay(
      stubs: [
        .get(
          "http://localhost:54321/auth/v1/admin/oauth/clients/E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          200, [:],
          {
            """
            {
              "client_id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
              "client_name": "Test Client",
              "client_type": "confidential",
              "token_endpoint_auth_method": "client_secret_post",
              "registration_type": "manual",
              "redirect_uris": ["https://example.com/callback"],
              "grant_types": ["authorization_code", "refresh_token"],
              "response_types": ["code"],
              "created_at": "2024-01-01T00:00:00.000Z",
              "updated_at": "2024-01-01T00:00:00.000Z"
            }
            """
          }
        )
      ], matching: [.method, .path], scope: .test
    )
  )
  func getOAuthClient() async throws {
    let sut = makeSUT()

    let client = try await sut.admin.oauth.getClient(clientId: clientId)

    #expect(client.clientId == clientId)
    #expect(client.clientName == "Test Client")
  }

  @Test(
    .replay(
      stubs: [
        .delete(
          "http://localhost:54321/auth/v1/admin/oauth/clients/E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
          200, [:],
          {
            """
            {
              "client_id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
              "client_name": "Test Client",
              "client_type": "confidential",
              "token_endpoint_auth_method": "client_secret_post",
              "registration_type": "manual",
              "redirect_uris": ["https://example.com/callback"],
              "grant_types": ["authorization_code", "refresh_token"],
              "response_types": ["code"],
              "created_at": "2024-01-01T00:00:00.000Z",
              "updated_at": "2024-01-01T00:00:00.000Z"
            }
            """
          }
        )
      ], matching: [.method, .path], scope: .test
    )
  )
  func deleteOAuthClient() async throws {
    let sut = makeSUT()

    let client = try await sut.admin.oauth.deleteClient(clientId: clientId)

    #expect(client.clientId == clientId)
  }

  @Test(
    .replay(
      stubs: [
        .post(
          "http://localhost:54321/auth/v1/admin/oauth/clients/E621E1F8-C36C-495A-93FC-0C247A3E6E5F/regenerate_secret",
          200, [:],
          {
            """
            {
              "client_id": "E621E1F8-C36C-495A-93FC-0C247A3E6E5F",
              "client_name": "Test Client",
              "client_secret": "new-secret456",
              "client_type": "confidential",
              "token_endpoint_auth_method": "client_secret_post",
              "registration_type": "manual",
              "redirect_uris": ["https://example.com/callback"],
              "grant_types": ["authorization_code", "refresh_token"],
              "response_types": ["code"],
              "created_at": "2024-01-01T00:00:00.000Z",
              "updated_at": "2024-01-01T00:00:00.000Z"
            }
            """
          }
        )
      ], matching: [.method, .path], scope: .test
    )
  )
  func regenerateOAuthClientSecret() async throws {
    let sut = makeSUT()

    let client = try await sut.admin.oauth.regenerateClientSecret(clientId: clientId)

    #expect(client.clientId == clientId)
    #expect(client.clientSecret == "new-secret456")
  }
}
