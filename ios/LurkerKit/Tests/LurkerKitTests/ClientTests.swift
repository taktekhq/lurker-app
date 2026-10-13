import Foundation
import Testing
@testable import LurkerKit

/// A `Transport` fake that records the last request it was asked to send
/// and returns a scripted response, so these tests never touch the network.
final class FakeTransport: Transport, @unchecked Sendable {
    var lastRequest: URLRequest?
    var statusCode = 200
    var responseData = Data("{}".utf8)

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://worker.example")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}

@Suite("Client request building for SPEC-v2.md's queue routes")
struct ClientTests {
    private func makeClient(_ transport: FakeTransport) -> Client {
        Client(base: URL(string: "https://worker.example")!, token: "t", transport: transport)
    }

    @Test("GET /v1/queues sends no body and decodes the full response")
    func queuesDecoding() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("""
        {"day":"2026-10-13","platforms":{
          "reddit":{"post":{"open":[],"done_today":1,"skipped_today":0,"target":5},
                    "comment":{"open":[],"done_today":0,"skipped_today":0,"target":5}},
          "hn":{"post":{"open":[],"done_today":0,"skipped_today":0,"target":5},
                "comment":{"open":[],"done_today":0,"skipped_today":0,"target":5}}
        }}
        """.utf8)
        let client = makeClient(transport)

        let result = try await client.queues()
        #expect(result.day == "2026-10-13")
        #expect(result.platforms.reddit.post.doneToday == 1)
        #expect(transport.lastRequest?.httpMethod == "GET")
        #expect(transport.lastRequest?.url?.path == "/v1/queues")
        #expect(transport.lastRequest?.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }

    @Test("done sends the link it is given")
    func doneWithLink() async throws {
        let transport = FakeTransport()
        let client = makeClient(transport)

        try await client.itemDone(id: "a1", link: "https://reddit.com/x")
        #expect(transport.lastRequest?.httpMethod == "POST")
        #expect(transport.lastRequest?.url?.path == "/v1/items/a1/done")
        let body = try #require(transport.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(json == ["link": "https://reddit.com/x"])
    }

    @Test("done with no link sends an empty body, asking the engine to find it")
    func doneWithoutLink() async throws {
        let transport = FakeTransport()
        let client = makeClient(transport)

        try await client.itemDone(id: "a1", link: nil)
        let body = try #require(transport.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(json == [:])
    }

    @Test("skip sends the reason and trims a blank note to nil")
    func skipTrimsBlankNote() async throws {
        let transport = FakeTransport()
        let client = makeClient(transport)

        try await client.itemSkip(id: "a1", reason: .bad, note: "   ")
        #expect(transport.lastRequest?.url?.path == "/v1/items/a1/skip")
        let body = try #require(transport.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["reason"] as? String == "bad")
        #expect(json?["note"] == nil)
    }

    @Test("skip keeps a real note")
    func skipKeepsNote() async throws {
        let transport = FakeTransport()
        let client = makeClient(transport)

        try await client.itemSkip(id: "a1", reason: .later, note: "not today")
        let body = try #require(transport.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(json?["reason"] as? String == "later")
        #expect(json?["note"] as? String == "not today")
    }

    @Test("link sends the new link to the right path")
    func linkRequest() async throws {
        let transport = FakeTransport()
        let client = makeClient(transport)

        try await client.itemLink(id: "a1", link: "https://reddit.com/fixed")
        #expect(transport.lastRequest?.httpMethod == "POST")
        #expect(transport.lastRequest?.url?.path == "/v1/items/a1/link")
        let body = try #require(transport.lastRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: String]
        #expect(json == ["link": "https://reddit.com/fixed"])
    }

    @Test("GET /v1/growth decodes an empty object without throwing")
    func growthEmpty() async throws {
        let transport = FakeTransport()
        transport.responseData = Data("{}".utf8)
        let client = makeClient(transport)

        let growth = try await client.growth()
        #expect(growth.isEmpty)
        #expect(transport.lastRequest?.url?.path == "/v1/growth")
    }

    @Test("a non-2xx response throws a decoded APIError")
    func errorResponse() async throws {
        let transport = FakeTransport()
        transport.statusCode = 401
        transport.responseData = Data("""
        {"error": "unauthorized"}
        """.utf8)
        let client = makeClient(transport)

        await #expect(throws: APIError(status: 401, message: "unauthorized")) {
            _ = try await client.queues()
        }
    }
}
