import Testing
@testable import OrganizerCore

@Suite("File classification")
struct OrganizationRuleTests {
    @Test func images() {
        #expect(OrganizationRule.category(forFileNamed: "photo.jpg", extension: "jpg") == .images)
        #expect(OrganizationRule.category(forFileNamed: "photo.HEIC", extension: "HEIC") == .images)
    }

    @Test func videos() {
        #expect(OrganizationRule.category(forFileNamed: "clip.mov", extension: "mov") == .videos)
    }

    @Test func documents() {
        #expect(OrganizationRule.category(forFileNamed: "resume.pdf", extension: "pdf") == .documents)
    }

    @Test func audio() {
        #expect(OrganizationRule.category(forFileNamed: "song.mp3", extension: "mp3") == .audio)
    }

    @Test func archives() {
        #expect(OrganizationRule.category(forFileNamed: "bundle.zip", extension: "zip") == .archives)
    }

    @Test func installers() {
        #expect(OrganizationRule.category(forFileNamed: "App.dmg", extension: "dmg") == .installers)
        #expect(OrganizationRule.category(forFileNamed: "App.pkg", extension: "pkg") == .installers)
    }

    @Test func unknownFallsBackToOther() {
        #expect(OrganizationRule.category(forFileNamed: "mystery.xyz", extension: "xyz") == .other)
        #expect(OrganizationRule.category(forFileNamed: "no-extension", extension: "") == .other)
    }

    @Test func screenshotsDetectedByNameAndImageExtension() {
        #expect(OrganizationRule.category(forFileNamed: "Screenshot 2026-09-29 at 10.15.22 AM.png", extension: "png") == .screenshots)
        #expect(OrganizationRule.category(forFileNamed: "Screen Recording 2026-09-29.mov", extension: "mov") == .screenshots)
        #expect(OrganizationRule.category(forFileNamed: "CleanShot 2026-09-29.png", extension: "png") == .screenshots)
    }

    @Test func screenshotNameOnlyAppliesToImageOrVideoExtensions() {
        // A file that merely starts with "Screenshot" but isn't an image/video
        // extension should classify by extension, not as a screenshot.
        #expect(OrganizationRule.category(forFileNamed: "Screenshot notes.pdf", extension: "pdf") == .documents)
    }

    @Test func screenshotPrefixRequiresWordBoundary() {
        // "Screenshotter.png" should NOT match the "Screenshot" prefix (no word boundary).
        #expect(OrganizationRule.category(forFileNamed: "Screenshotter.png", extension: "png") == .images)
    }
}
