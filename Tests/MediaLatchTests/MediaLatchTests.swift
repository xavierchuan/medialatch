import XCTest
@testable import MediaLatch

final class MediaLatchTests: XCTestCase {
    func testStreamingDownloadsForceProgressOutput() {
        XCTAssertTrue(YTDLPService.downloadProgressArguments.contains("--newline"))
        XCTAssertTrue(YTDLPService.downloadProgressArguments.contains("--progress"))
        XCTAssertTrue(YTDLPService.downloadProgressArguments.contains("--no-colors"))
    }

    func testShareLinks() {
        let link = "https://www.bilibili.com/video/BV13P411H7mo/?p=2&spm_id_from=333"
        XCTAssertEqual(ShareLink.extract(from: "【埙独奏】复制链接：\n" + link + " 打开观看"), link)
        XCTAssertEqual(ShareLink.extract(from: link), link)
        XCTAssertEqual(ShareLink.extract(from: "分享 https://xhslink.com/a/AbC 。"), "https://xhslink.com/a/AbC")
        XCTAssertNil(ShareLink.extract(from: "没有链接"))
        XCTAssertNil(ShareLink.extract(from: "file:///etc/hosts"))
    }

    func testRednotePublicGalleryKeepsOrderAndMetadata() throws {
        let url = try XCTUnwrap(URL(string: "https://www.xiaohongshu.com/explore/674051740000000007027a15"))
        let html = #"""
        <script>window.__INITIAL_STATE__ = {"unused":undefined,"note":{"noteDetailMap":{
          "674051740000000007027a15":{"note":{"type":"normal","title":"旅行相册","desc":"保留 undefined 原文",
          "user":{"nickname":"作者"},"imageList":[
            {"urlDefault":"http://sns-webpic.xhscdn.com/first.jpg"},
            {"infoList":[{"url":"https://sns-webpic.xhscdn.com/second.jpg"}]}
          ]}}
        }}};</script>
        """#
        let note = try XCTUnwrap(RednoteGallery.parse(html, source: url, page: url))
        XCTAssertEqual(note.gallery.map(\.absoluteString), [
            "https://sns-webpic.xhscdn.com/first.jpg", "https://sns-webpic.xhscdn.com/second.jpg",
        ])
        XCTAssertEqual(note.copyText, "旅行相册\n\n保留 undefined 原文")
        XCTAssertNil(RednoteGallery.parse("<title>Log in</title>", source: url, page: url))
    }

    func testDurationFormatting() {
        let media = MediaInfo(
            id: "test",
            sourceURL: "https://example.com/video",
            title: "Test",
            creator: "Creator",
            thumbnailURL: nil,
            duration: 3_876,
            availableHeights: [2160, 1080]
        )
        XCTAssertEqual(media.durationText, "1:04:36")
        XCTAssertEqual(media.bestQualityText, "2160p")
    }
}
