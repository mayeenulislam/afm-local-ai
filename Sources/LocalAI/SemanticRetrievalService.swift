import Foundation
import NaturalLanguage

struct SemanticRetrievalService: Sendable {
    private let maximumTextCharacters = 1_200

    // ponytail: process-wide vector cache — chunk embeddings never change per query,
    // so encode each unique chunk text once per session instead of once per tool run.
    // Upgrade path: persist vectors in the chunk index to also skip the first-run cost.
    private static let cacheLock = NSLock()
    private nonisolated(unsafe) static var vectorCache: [String: [Double]] = [:]

    private static func cachedVector(for key: String) -> [Double]? {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        return vectorCache[key]
    }

    private static func cacheVector(_ vector: [Double], for key: String) {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        vectorCache[key] = vector
    }

    var status: SemanticRetrievalSummary {
        if NLEmbedding.sentenceEmbedding(for: .english) != nil {
            return SemanticRetrievalSummary(provider: "NaturalLanguage sentence embeddings", isAvailable: true)
        }
        return SemanticRetrievalSummary(provider: "NaturalLanguage sentence embeddings", isAvailable: false)
    }

    func rankedChunks(query: String, chunks: [TextChunk], limit: Int) -> [SemanticChunkScore] {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: .english),
              let queryVector = embedding.vector(for: normalized(query)) else {
            return []
        }

        return chunks
            .compactMap { chunk -> SemanticChunkScore? in
                autoreleasepool {
                    guard !Task.isCancelled else { return nil }
                    let semanticText = normalized(searchableText(for: chunk))
                    let chunkVector: [Double]?
                    if let cached = Self.cachedVector(for: semanticText) {
                        chunkVector = cached
                    } else if let vector = embedding.vector(for: semanticText) {
                        Self.cacheVector(vector, for: semanticText)
                        chunkVector = vector
                    } else {
                        chunkVector = nil
                    }
                    guard let chunkVector else { return nil }

                    let similarity = cosineSimilarity(queryVector, chunkVector)
                    guard similarity.isFinite else { return nil }
                    return SemanticChunkScore(chunk: chunk, score: similarity)
                }
            }
            .sorted { left, right in
                if left.score == right.score {
                    return left.chunk.filePath.localizedStandardCompare(right.chunk.filePath) == .orderedAscending
                }
                return left.score > right.score
            }
            .prefix(limit)
            .map { $0 }
    }

    private func searchableText(for chunk: TextChunk) -> String {
        [
            chunk.filePath,
            chunk.title ?? "",
            chunk.obsidianTags?.joined(separator: " ") ?? "",
            chunk.obsidianWikilinks?.joined(separator: " ") ?? "",
            chunk.content
        ]
        .joined(separator: "\n")
    }

    private func normalized(_ text: String) -> String {
        let compact = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .joined(separator: " ")
        if compact.count <= maximumTextCharacters {
            return compact
        }
        return String(compact.prefix(maximumTextCharacters))
    }

    private func cosineSimilarity(_ left: [Double], _ right: [Double]) -> Double {
        guard left.count == right.count, !left.isEmpty else { return 0 }

        var dot = 0.0
        var leftMagnitude = 0.0
        var rightMagnitude = 0.0
        for index in left.indices {
            dot += left[index] * right[index]
            leftMagnitude += left[index] * left[index]
            rightMagnitude += right[index] * right[index]
        }

        guard leftMagnitude > 0, rightMagnitude > 0 else { return 0 }
        return dot / (sqrt(leftMagnitude) * sqrt(rightMagnitude))
    }
}

struct SemanticChunkScore: Sendable {
    var chunk: TextChunk
    var score: Double
}
