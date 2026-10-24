import CryptoKit
import Foundation
import SQLite3

struct ChunkIndexStore: Sendable {
    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private var decoder: JSONDecoder {
        JSONDecoder()
    }

    func save(chunks: [TextChunk], for workspace: Workspace) throws -> (jsonURL: URL, sqliteURL: URL) {
        let directory = try indexDirectory(for: workspace)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        AppSupport.secure(directory, isDirectory: true)
        AppSupport.secure(directory.deletingLastPathComponent(), isDirectory: true)
        let jsonURL = directory.appendingPathComponent("chunks.json")
        let data = try encoder.encode(chunks)
        try data.write(to: jsonURL, options: .atomic)
        AppSupport.secure(jsonURL, isDirectory: false)

        let sqliteURL = directory.appendingPathComponent("chunks.sqlite")
        try saveSearchIndex(chunks: chunks, to: sqliteURL)
        AppSupport.secure(sqliteURL, isDirectory: false)
        return (jsonURL, sqliteURL)
    }

    func load(for workspace: Workspace) throws -> [TextChunk] {
        let url = try indexDirectory(for: workspace).appendingPathComponent("chunks.json")
        let data = try Data(contentsOf: url)
        return try decoder.decode([TextChunk].self, from: data)
    }

    private func indexDirectory(for workspace: Workspace) throws -> URL {
        try indexDirectoryForPath(workspace.path)
    }

    private func indexDirectoryForPath(_ path: String) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let workspaceKey = stableWorkspaceKey(path)
        return base
            .appendingPathComponent(AppSupport.directoryName, isDirectory: true)
            .appendingPathComponent("Indexes", isDirectory: true)
            .appendingPathComponent(workspaceKey, isDirectory: true)
    }

    private func stableWorkspaceKey(_ path: String) -> String {
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    func deleteIndex(for path: String) {
        guard let dir = try? indexDirectoryForPath(path) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    func search(workspace: Workspace, query: String, limit: Int) throws -> [TextChunk] {
        let sqliteURL = try indexDirectory(for: workspace).appendingPathComponent("chunks.sqlite")
        let safeQuery = ftsQuery(from: query)
        guard !safeQuery.isEmpty else {
            return Array(try load(for: workspace).prefix(limit))
        }

        return try withDatabase(at: sqliteURL) { database in
            let sql = """
            SELECT workspace_path, file_path, file_kind, title, content, ordinal, start_line, end_line, page_number, slide_number, obsidian_tags, obsidian_wikilinks, obsidian_frontmatter, token_estimate, content_hash
            FROM chunks
            WHERE chunks MATCH ?
            ORDER BY rank
            LIMIT ?;
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                throw SQLiteIndexError.prepare(message: errorMessage(database))
            }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, safeQuery, -1, transientDestructor)
            sqlite3_bind_int(statement, 2, Int32(limit))

            var chunks: [TextChunk] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                chunks.append(
                    TextChunk(
                        workspacePath: columnText(statement, 0),
                        filePath: columnText(statement, 1),
                        fileKind: columnText(statement, 2),
                        title: optionalColumnText(statement, 3),
                        content: columnText(statement, 4),
                        ordinal: Int(sqlite3_column_int(statement, 5)),
                        startLine: optionalColumnInt(statement, 6),
                        endLine: optionalColumnInt(statement, 7),
                        pageNumber: optionalColumnInt(statement, 8),
                        slideNumber: optionalColumnInt(statement, 9),
                        obsidianTags: decodeOptional([String].self, from: optionalColumnText(statement, 10)),
                        obsidianWikilinks: decodeOptional([String].self, from: optionalColumnText(statement, 11)),
                        obsidianFrontmatter: decodeOptional([String: String].self, from: optionalColumnText(statement, 12)),
                        tokenEstimate: Int(sqlite3_column_int(statement, 13)),
                        contentHash: columnText(statement, 14)
                    )
                )
            }
            return chunks
        }
    }

    private func saveSearchIndex(chunks: [TextChunk], to url: URL) throws {
        try withDatabase(at: url) { database in
            // BEGIN IMMEDIATE takes the write lock up front so concurrent
            // writers queue on the busy timeout instead of racing drop/create.
            try execute("BEGIN IMMEDIATE TRANSACTION;", database: database)
            do {
                try execute(
                    """
                    DROP TABLE IF EXISTS chunks;
                    """,
                    database: database
                )
                try execute(
                    """
                    CREATE VIRTUAL TABLE chunks USING fts5(
                        workspace_path UNINDEXED,
                        file_path,
                        file_kind UNINDEXED,
                        title,
                        content,
                        ordinal UNINDEXED,
                        start_line UNINDEXED,
                        end_line UNINDEXED,
                        page_number UNINDEXED,
                        slide_number UNINDEXED,
                        obsidian_tags,
                        obsidian_wikilinks,
                        obsidian_frontmatter,
                        token_estimate UNINDEXED,
                        content_hash UNINDEXED
                    );
                    """,
                    database: database
                )

                let sql = """
                INSERT INTO chunks (
                    workspace_path, file_path, file_kind, title, content, ordinal,
                    start_line, end_line, page_number, slide_number,
                    obsidian_tags, obsidian_wikilinks, obsidian_frontmatter,
                    token_estimate, content_hash
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
                var statement: OpaquePointer?
                guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
                    throw SQLiteIndexError.prepare(message: errorMessage(database))
                }
                defer { sqlite3_finalize(statement) }

                for chunk in chunks {
                    sqlite3_bind_text(statement, 1, chunk.workspacePath, -1, transientDestructor)
                    sqlite3_bind_text(statement, 2, chunk.filePath, -1, transientDestructor)
                    sqlite3_bind_text(statement, 3, chunk.fileKind, -1, transientDestructor)
                    if let title = chunk.title {
                        sqlite3_bind_text(statement, 4, title, -1, transientDestructor)
                    } else {
                        sqlite3_bind_null(statement, 4)
                    }
                    sqlite3_bind_text(statement, 5, chunk.content, -1, transientDestructor)
                    sqlite3_bind_int(statement, 6, Int32(chunk.ordinal))
                    bindOptionalInt(chunk.startLine, index: 7, statement: statement)
                    bindOptionalInt(chunk.endLine, index: 8, statement: statement)
                    bindOptionalInt(chunk.pageNumber, index: 9, statement: statement)
                    bindOptionalInt(chunk.slideNumber, index: 10, statement: statement)
                    bindOptionalJSON(chunk.obsidianTags, index: 11, statement: statement)
                    bindOptionalJSON(chunk.obsidianWikilinks, index: 12, statement: statement)
                    bindOptionalJSON(chunk.obsidianFrontmatter, index: 13, statement: statement)
                    sqlite3_bind_int(statement, 14, Int32(chunk.tokenEstimate))
                    sqlite3_bind_text(statement, 15, chunk.contentHash, -1, transientDestructor)

                    guard sqlite3_step(statement) == SQLITE_DONE else {
                        throw SQLiteIndexError.insert(message: errorMessage(database))
                    }
                    sqlite3_reset(statement)
                    sqlite3_clear_bindings(statement)
                }
                try execute("COMMIT;", database: database)
            } catch {
                try? execute("ROLLBACK;", database: database)
                throw error
            }
        }
    }

    private func withDatabase<T>(at url: URL, body: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else {
            throw SQLiteIndexError.open(message: database.map(errorMessage) ?? "Unable to open SQLite database.")
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 5000)
        return try body(database)
    }

    private func execute(_ sql: String, database: OpaquePointer) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteIndexError.execute(message: errorMessage(database))
        }
    }

    private func ftsQuery(from text: String) -> String {
        text
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { $0.count > 2 }
            .prefix(10)
            .map { "\"\($0.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            .joined(separator: " OR ")
    }

    private var transientDestructor: sqlite3_destructor_type {
        unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    }

    private func bindOptionalInt(_ value: Int?, index: Int32, statement: OpaquePointer?) {
        if let value {
            sqlite3_bind_int(statement, index, Int32(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bindOptionalJSON<T: Encodable>(_ value: T?, index: Int32, statement: OpaquePointer?) {
        guard let value,
              let data = try? encoder.encode(value),
              let json = String(data: data, encoding: .utf8) else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, json, -1, transientDestructor)
    }

    private func decodeOptional<T: Decodable>(_ type: T.Type, from json: String?) -> T? {
        guard let json,
              let data = json.data(using: .utf8) else {
            return nil
        }
        return try? decoder.decode(type, from: data)
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func optionalColumnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return columnText(statement, index)
    }

    private func optionalColumnInt(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    private func errorMessage(_ database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else { return "Unknown SQLite error." }
        return String(cString: message)
    }
}

enum SQLiteIndexError: LocalizedError, Sendable {
    case open(message: String)
    case prepare(message: String)
    case execute(message: String)
    case insert(message: String)

    var errorDescription: String? {
        switch self {
        case .open(let message):
            "Could not open chunk search index: \(message)"
        case .prepare(let message):
            "Could not prepare chunk search query: \(message)"
        case .execute(let message):
            "Could not update chunk search index: \(message)"
        case .insert(let message):
            "Could not insert chunk into search index: \(message)"
        }
    }
}
