import Foundation
import Testing
@testable import LurkerKit

@Suite("Multipart")
struct MultipartTests {
    @Test("includes the note field and each photo as a repeated photo field, in order")
    func bodyShape() throws {
        let multipart = Multipart(boundary: "TestBoundary123")
        let photos = [Data([0xFF, 0xD8, 0xAA, 0xBB]), Data([0xFF, 0xD8, 0xCC, 0xDD])]
        let body = multipart.body(note: "a short note", photos: photos)
        let text = String(decoding: body, as: UTF8.self)

        #expect(multipart.contentType == "multipart/form-data; boundary=TestBoundary123")
        #expect(text.contains("--TestBoundary123\r\n"))
        #expect(text.contains("Content-Disposition: form-data; name=\"note\"\r\n\r\na short note\r\n"))
        #expect(text.contains("Content-Disposition: form-data; name=\"photo\"; filename=\"photo1.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"))
        #expect(text.contains("Content-Disposition: form-data; name=\"photo\"; filename=\"photo2.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"))
        #expect(text.hasSuffix("--TestBoundary123--\r\n"))

        // Field order: note, then each photo in the order it was given.
        let noteRange = try #require(text.range(of: "name=\"note\""))
        let photo1Range = try #require(text.range(of: "filename=\"photo1.jpg\""))
        let photo2Range = try #require(text.range(of: "filename=\"photo2.jpg\""))
        #expect(noteRange.lowerBound < photo1Range.lowerBound)
        #expect(photo1Range.lowerBound < photo2Range.lowerBound)

        // The raw photo bytes are carried through untouched.
        #expect(body.range(of: photos[0]) != nil)
        #expect(body.range(of: photos[1]) != nil)
    }

    @Test("omits the note field entirely when note is nil")
    func nilNoteOmitted() {
        let multipart = Multipart(boundary: "B")
        let body = multipart.body(note: nil, photos: [Data([0x01])])
        let text = String(decoding: body, as: UTF8.self)
        #expect(!text.contains("name=\"note\""))
    }

    @Test("omits the note field entirely when note is empty")
    func emptyNoteOmitted() {
        let multipart = Multipart(boundary: "B")
        let body = multipart.body(note: "", photos: [Data([0x01])])
        let text = String(decoding: body, as: UTF8.self)
        #expect(!text.contains("name=\"note\""))
    }

    @Test("a single photo and no note still closes the body correctly")
    func singlePhotoNoNote() {
        let multipart = Multipart(boundary: "B")
        let body = multipart.body(note: nil, photos: [Data([0xFF, 0xD8])])
        let text = String(decoding: body, as: UTF8.self)
        let photoFieldCount = text.components(separatedBy: "name=\"photo\"").count - 1
        #expect(photoFieldCount == 1)
        #expect(text.hasSuffix("--B--\r\n"))
    }

    @Test("ten photos produce ten repeated photo fields, numbered in order")
    func tenPhotos() {
        let multipart = Multipart(boundary: "B")
        let photos = (1...10).map { Data([UInt8($0)]) }
        let body = multipart.body(note: nil, photos: photos)
        let text = String(decoding: body, as: UTF8.self)
        let photoFieldCount = text.components(separatedBy: "name=\"photo\"").count - 1
        #expect(photoFieldCount == 10)
        #expect(text.contains("filename=\"photo1.jpg\""))
        #expect(text.contains("filename=\"photo10.jpg\""))
    }
}
