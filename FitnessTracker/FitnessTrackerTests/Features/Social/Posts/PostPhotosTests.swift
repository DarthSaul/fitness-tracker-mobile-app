import Foundation
import Testing
@testable import FitnessTracker

struct PostPhotosTests {
    private func photo(width: Int, height: Int) -> PostPhotoDTO {
        PostPhotoDTO(id: "p1", url: "https://example.com/p1.jpg", width: width, height: height)
    }

    @Test func squarePhotoKeepsItsShape() {
        #expect(PostPhotos.displayAspectRatio(for: photo(width: 1000, height: 1000)) == 1)
    }

    @Test func photoWithinLimitsKeepsItsShape() {
        let ratio = PostPhotos.displayAspectRatio(for: photo(width: 1600, height: 1200))
        #expect(abs(ratio - 4.0 / 3.0) < 0.0001)
    }

    @Test func veryTallPhotoIsClampedToThreeByFour() {
        #expect(PostPhotos.displayAspectRatio(for: photo(width: 1000, height: 4000)) == 3.0 / 4.0)
    }

    @Test func veryWidePhotoIsClampedToSixteenByNine() {
        #expect(PostPhotos.displayAspectRatio(for: photo(width: 4000, height: 1000)) == 16.0 / 9.0)
    }

    @Test func zeroDimensionsFallBackToSquare() {
        #expect(PostPhotos.displayAspectRatio(for: photo(width: 0, height: 0)) == 1)
    }
}
