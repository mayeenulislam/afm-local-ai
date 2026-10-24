import Foundation

struct TaskExecutionService: Sendable {
    var extractor = TextExtractor()
    var chunker = TextChunker()
    var indexStore = ChunkIndexStore()
    var obsidianParser = ObsidianMetadataParser()
    var gitReader = GitWorkspaceReader()
    var semanticRetriever = SemanticRetrievalService()

    func buildIndex(for workspace: Workspace, includeGitSnapshot: Bool = true) throws -> ChunkIndexSummary {
        let ignoreRules = WorkspaceIgnoreRules(root: workspace.url)
        var chunks: [TextChunk] = []
        var indexedFiles = 0
        var skippedFiles = 0
        var ignoredFiles = 0
        var obsidianAccumulator = ObsidianIndexAccumulator()
        var gitSummary: GitWorkspaceSummary?

        for file in workspace.files {
            try Task.checkCancellation()

            if ignoreRules.shouldSkip(url: file.url, root: workspace.url, isDirectory: false) {
                ignoredFiles += 1
                continue
            }

            do {
                let extraction = try extractor.extract(from: file)
                let metadata = file.kind == .markdown ? obsidianParser.parse(extraction.text) : nil
                let chunkExtraction: TextExtractionResult
                if let metadata, !metadata.bodyText.isEmpty {
                    chunkExtraction = TextExtractionResult(
                        text: metadata.bodyText,
                        lineCount: metadata.bodyText.split(separator: "\n", omittingEmptySubsequences: false).count
                    )
                    obsidianAccumulator.record(metadata)
                } else {
                    chunkExtraction = extraction
                }

                var fileChunks = chunker.chunks(for: file, workspace: workspace, extraction: chunkExtraction)
                if let metadata {
                    fileChunks = fileChunks.map { chunk in
                        var enriched = chunk
                        enriched.obsidianTags = metadata.tags.isEmpty ? nil : metadata.tags
                        enriched.obsidianWikilinks = metadata.wikilinks.isEmpty ? nil : metadata.wikilinks
                        enriched.obsidianFrontmatter = metadata.frontmatter.isEmpty ? nil : metadata.frontmatter
                        return enriched
                    }
                }
                if fileChunks.isEmpty {
                    skippedFiles += 1
                } else {
                    indexedFiles += 1
                    chunks.append(contentsOf: fileChunks)
                }
            } catch {
                skippedFiles += 1
            }
        }

        try Task.checkCancellation()
        if includeGitSnapshot, let gitSnapshot = gitReader.snapshot(for: workspace.url) {
            let gitFile = WorkspaceFile(
                url: workspace.url.appendingPathComponent(".git"),
                relativePath: ".git",
                kind: .code,
                byteCount: Int64(gitSnapshot.markdown.utf8.count)
            )
            let extraction = TextExtractionResult(
                text: gitSnapshot.markdown,
                lineCount: gitSnapshot.markdown.split(separator: "\n", omittingEmptySubsequences: false).count
            )
            let gitChunks = chunker.chunks(for: gitFile, workspace: workspace, extraction: extraction)
            if !gitChunks.isEmpty {
                chunks.append(contentsOf: gitChunks)
                gitSummary = gitSnapshot.summary
            }
        }

        try Task.checkCancellation()
        let persisted = try indexStore.save(chunks: chunks, for: workspace)
        var semanticSummary = semanticRetriever.status
        semanticSummary.embeddedChunks = semanticSummary.isAvailable ? chunks.count : 0
        return ChunkIndexSummary(
            chunks: chunks,
            indexedFiles: indexedFiles,
            skippedFiles: skippedFiles,
            ignoredFiles: ignoredFiles,
            persistedURL: persisted.jsonURL,
            searchIndexURL: persisted.sqliteURL,
            obsidianSummary: obsidianAccumulator.summary,
            gitSummary: gitSummary,
            semanticSummary: semanticSummary
        )
    }

    func selectChunks(for template: TaskTemplate, workspace: Workspace, from chunks: [TextChunk], budget: ContextBudget) throws -> [TextChunk] {
        try Task.checkCancellation()
        var selected: [TextChunk] = []
        var tokenCount = 0

        if template.title == "Explain Codebase",
           let overview = overviewChunk(for: workspace, from: chunks, tokenCap: max(1, Int(Double(budget.selectedChunks) * 0.5))) {
            selected.append(overview)
            tokenCount = overview.tokenEstimate
        }

        let ranked = rankedChunks(for: template, workspace: workspace, from: chunks)

        for chunk in ranked {
            guard tokenCount + chunk.tokenEstimate <= budget.selectedChunks else {
                continue
            }
            selected.append(chunk)
            tokenCount += chunk.tokenEstimate
            if selected.count >= 12 { break }
        }

        if selected.isEmpty {
            for chunk in chunks.prefix(8) {
                guard tokenCount + chunk.tokenEstimate <= budget.selectedChunks else { break }
                selected.append(chunk)
                tokenCount += chunk.tokenEstimate
            }
        }

        return selected
    }

    private func rankedChunks(for template: TaskTemplate, workspace: Workspace, from chunks: [TextChunk]) -> [TextChunk] {
        let keywords = keywords(for: template)
        let ftsMatches = (try? indexStore.search(workspace: workspace, query: "\(template.title) \(template.prompt)", limit: 40)) ?? []
        let query = "\(template.title) \(template.subtitle) \(template.prompt)"
        let pool = semanticCandidatePool(chunks: chunks, ftsMatches: ftsMatches, keywords: keywords, limit: Self.semanticPoolLimit)
        let semanticMatches = semanticRetriever.rankedChunks(query: query, chunks: pool, limit: 40)
        return blendedRanking(
            chunks: chunks,
            ftsMatches: ftsMatches,
            semanticMatches: semanticMatches,
            keywords: keywords
        )
    }

    static let semanticPoolLimit = 60

    func semanticCandidatePool(chunks: [TextChunk], ftsMatches: [TextChunk], keywords: [String], limit: Int) -> [TextChunk] {
        guard limit > 0 else { return [] }
        var seen = Set<String>()
        var pool: [TextChunk] = []
        for chunk in ftsMatches {
            let key = stableKey(for: chunk)
            guard seen.insert(key).inserted else { continue }
            pool.append(chunk)
            if pool.count >= limit { return pool }
        }
        let ranked = chunks
            .map { (score($0, keywords: keywords), $0) }
            .sorted { $0.0 > $1.0 }
            .map(\.1)
        for chunk in ranked {
            let key = stableKey(for: chunk)
            guard seen.insert(key).inserted else { continue }
            pool.append(chunk)
            if pool.count >= limit { break }
        }
        return pool
    }

    private func overviewChunk(for workspace: Workspace, from chunks: [TextChunk], tokenCap: Int) -> TextChunk? {
        let firstLines = chunks.reduce(into: [String: String]()) { result, chunk in
            guard result[chunk.filePath] == nil, let line = firstMeaningfulLine(of: chunk) else { return }
            result[chunk.filePath] = line
        }
        var lines: [String] = []
        var tokens = 0
        for file in workspace.files.sorted(by: { $0.relativePath < $1.relativePath }) {
            let line = "\(file.kind.rawValue) \(file.relativePath) - \(firstLines[file.relativePath] ?? "no readable content")"
            let lineTokens = chunker.estimateTokens(line, kind: file.kind)
            guard tokens + lineTokens <= tokenCap else { break }
            lines.append(line)
            tokens += lineTokens
        }
        guard !lines.isEmpty else { return nil }
        return TextChunk(
            workspacePath: workspace.path,
            filePath: workspace.name,
            fileKind: "Summary",
            title: "Workspace overview",
            content: lines.joined(separator: "\n"),
            ordinal: 0,
            startLine: nil,
            endLine: nil,
            pageNumber: nil,
            slideNumber: nil,
            tokenEstimate: tokens,
            contentHash: "overview-\(workspace.path)"
        )
    }

    private func firstMeaningfulLine(of chunk: TextChunk) -> String? {
        guard let raw = chunk.content
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { $0.count >= 2 && $0 != "---" && $0 != "***" && !$0.hasPrefix("<!--") })
        else { return nil }
        let trimmed = raw.hasPrefix("#") ? String(raw.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)) : raw
        guard !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(90))
    }

    private func blendedRanking(
        chunks: [TextChunk],
        ftsMatches: [TextChunk],
        semanticMatches: [SemanticChunkScore],
        keywords: [String]
    ) -> [TextChunk] {
        var candidates: [String: TextChunk] = [:]
        let candidateSource = ftsMatches.isEmpty ? chunks : ftsMatches
        for chunk in candidateSource {
            candidates[stableKey(for: chunk)] = chunk
        }
        for match in semanticMatches {
            candidates[stableKey(for: match.chunk)] = match.chunk
        }

        let ftsRanks = rankMap(for: ftsMatches)
        let semanticScores = Dictionary(uniqueKeysWithValues: semanticMatches.map { (stableKey(for: $0.chunk), $0.score) })
        let keywordScores = Dictionary(uniqueKeysWithValues: candidates.values.map { (stableKey(for: $0), Double(score($0, keywords: keywords))) })

        return candidates.values.sorted { left, right in
            blendedScore(left, ftsRanks: ftsRanks, semanticScores: semanticScores, keywordScores: keywordScores)
                > blendedScore(right, ftsRanks: ftsRanks, semanticScores: semanticScores, keywordScores: keywordScores)
        }
    }

    private func blendedScore(
        _ chunk: TextChunk,
        ftsRanks: [String: Double],
        semanticScores: [String: Double],
        keywordScores: [String: Double]
    ) -> Double {
        let key = stableKey(for: chunk)
        let keywordScore = keywordScores[key] ?? 0
        let ftsScore = ftsRanks[key] ?? 0
        let semanticScore = semanticScores[key] ?? 0
        return keywordScore + ftsScore + (semanticScore * 4)
    }

    private func rankMap(for chunks: [TextChunk]) -> [String: Double] {
        guard !chunks.isEmpty else { return [:] }
        var result: [String: Double] = [:]
        for (index, chunk) in chunks.enumerated() {
            result[stableKey(for: chunk)] = Double(chunks.count - index) / Double(chunks.count)
        }
        return result
    }

    private func stableKey(for chunk: TextChunk) -> String {
        "\(chunk.filePath)#\(chunk.ordinal)#\(chunk.contentHash)"
    }

    private func keywords(for template: TaskTemplate) -> [String] {
        let text = "\(template.title) \(template.subtitle) \(template.prompt)"
        return text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 3 }
    }

    private func score(_ chunk: TextChunk, keywords: [String]) -> Int {
        let obsidian = [
            chunk.obsidianTags?.joined(separator: " ") ?? "",
            chunk.obsidianWikilinks?.joined(separator: " ") ?? "",
            chunk.obsidianFrontmatter?.map { "\($0.key) \($0.value)" }.joined(separator: " ") ?? ""
        ].joined(separator: " ")
        let haystack = "\(chunk.filePath) \(chunk.title ?? "") \(obsidian) \(chunk.content.prefix(800))".lowercased()
        return keywords.reduce(0) { total, keyword in
            total + (haystack.contains(keyword) ? 1 : 0)
        }
    }
}
