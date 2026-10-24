import Foundation
import SQLite3

struct SQLiteDataExtractor: Sendable {
    var maximumObjects = 30
    var sampleRowsPerObject = 3
    var maximumCellCharacters = 140

    func extractDatabaseSummary(from url: URL) throws -> String {
        try withReadOnlyDatabase(at: url) { database in
            let objects = try schemaObjects(in: database)
            guard !objects.isEmpty else {
                return "# SQLite Database: \(url.lastPathComponent)\n\nNo user tables or views were found."
            }

            var sections: [String] = [
                "# SQLite Database: \(url.lastPathComponent)",
                "Path: \(url.path)",
                "Objects inspected: \(objects.count)"
            ]

            for object in objects {
                sections.append(try describe(object: object, database: database))
            }

            return sections.joined(separator: "\n\n")
        }
    }

    private func schemaObjects(in database: OpaquePointer) throws -> [SQLiteSchemaObject] {
        let sql = """
        SELECT type, name, sql
        FROM sqlite_schema
        WHERE type IN ('table', 'view')
          AND name NOT LIKE 'sqlite_%'
        ORDER BY type, name
        LIMIT ?;
        """

        return try query(database: database, sql: sql, bindings: [.int(maximumObjects)]) { statement in
            SQLiteSchemaObject(
                type: columnText(statement, 0),
                name: columnText(statement, 1),
                sql: optionalColumnText(statement, 2) ?? ""
            )
        }
    }

    private func describe(object: SQLiteSchemaObject, database: OpaquePointer) throws -> String {
        var lines: [String] = [
            "## \(object.type.capitalized): \(object.name)"
        ]

        if !object.sql.isEmpty {
            lines.append("Schema:")
            lines.append("```sql\n\(object.sql)\n```")
        }

        let columns = try columns(for: object.name, database: database)
        if !columns.isEmpty {
            lines.append("Columns:")
            for column in columns {
                let primaryKey = column.isPrimaryKey ? " primary key" : ""
                let required = column.isNotNull ? " not null" : ""
                let defaultValue = column.defaultValue.map { " default \($0)" } ?? ""
                lines.append("- \(column.name) \(column.type)\(primaryKey)\(required)\(defaultValue)".trimmingCharacters(in: .whitespaces))
            }
        }

        let samples = object.type == "table"
            ? (try sampleRows(for: object.name, database: database))
            : (headers: [String](), rows: [[String]]())
        if samples.rows.isEmpty {
            lines.append("Sample rows: none")
        } else {
            lines.append("Sample rows:")
            lines.append(markdownTable(headers: samples.headers, rows: samples.rows))
        }

        return lines.joined(separator: "\n")
    }

    private func columns(for tableName: String, database: OpaquePointer) throws -> [SQLiteColumn] {
        let sql = "PRAGMA table_info(\(quotedIdentifier(tableName)));"
        return try query(database: database, sql: sql, bindings: []) { statement in
            SQLiteColumn(
                name: columnText(statement, 1),
                type: columnText(statement, 2),
                isNotNull: sqlite3_column_int(statement, 3) != 0,
                defaultValue: optionalColumnText(statement, 4),
                isPrimaryKey: sqlite3_column_int(statement, 5) != 0
            )
        }
    }

    private func sampleRows(for tableName: String, database: OpaquePointer) throws -> (headers: [String], rows: [[String]]) {
        let sql = "SELECT * FROM \(quotedIdentifier(tableName)) LIMIT \(sampleRowsPerObject);"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            return ([], [])
        }
        defer { sqlite3_finalize(statement) }

        let columnCount = Int(sqlite3_column_count(statement))
        guard columnCount > 0 else { return ([], []) }

        let headers = (0..<columnCount).map { index in
            String(cString: sqlite3_column_name(statement, Int32(index)))
        }

        var rows: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            rows.append((0..<columnCount).map { index in
                renderCell(statement: statement, index: Int32(index))
            })
        }

        return (headers, rows)
    }

    private func markdownTable(headers: [String], rows: [[String]]) -> String {
        guard !headers.isEmpty else { return "No columns." }
        let headerLine = "| \(headers.map(escapeMarkdownCell).joined(separator: " | ")) |"
        let separatorLine = "| \(headers.map { _ in "---" }.joined(separator: " | ")) |"
        let rowLines = rows.map { row in
            "| \(row.map(escapeMarkdownCell).joined(separator: " | ")) |"
        }
        return ([headerLine, separatorLine] + rowLines).joined(separator: "\n")
    }

    private func renderCell(statement: OpaquePointer?, index: Int32) -> String {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_NULL:
            return "NULL"
        case SQLITE_INTEGER:
            return String(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
            return String(sqlite3_column_double(statement, index))
        case SQLITE_BLOB:
            return "<blob \(sqlite3_column_bytes(statement, index)) bytes>"
        default:
            let value = columnText(statement, index)
            if value.count <= maximumCellCharacters {
                return value
            }
            let prefix = value.prefix(maximumCellCharacters)
            return "\(prefix)..."
        }
    }

    private func query<T>(database: OpaquePointer, sql: String, bindings: [SQLiteBinding], map: (OpaquePointer?) throws -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteDataExtractionError.prepare(message: errorMessage(database))
        }
        defer { sqlite3_finalize(statement) }

        for (offset, binding) in bindings.enumerated() {
            switch binding {
            case .int(let value):
                sqlite3_bind_int(statement, Int32(offset + 1), Int32(value))
            }
        }

        var results: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            results.append(try map(statement))
        }
        return results
    }

    private func withReadOnlyDatabase<T>(at url: URL, body: (OpaquePointer) throws -> T) throws -> T {
        var database: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(url.path, &database, flags, nil) == SQLITE_OK, let database else {
            throw SQLiteDataExtractionError.open(message: database.map(errorMessage) ?? "Unable to open SQLite database.")
        }
        defer { sqlite3_close(database) }
        return try body(database)
    }

    private func quotedIdentifier(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private func escapeMarkdownCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
    }

    private func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    private func optionalColumnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return columnText(statement, index)
    }

    private func errorMessage(_ database: OpaquePointer) -> String {
        guard let message = sqlite3_errmsg(database) else { return "Unknown SQLite error." }
        return String(cString: message)
    }
}

private struct SQLiteSchemaObject: Sendable {
    var type: String
    var name: String
    var sql: String
}

private struct SQLiteColumn: Sendable {
    var name: String
    var type: String
    var isNotNull: Bool
    var defaultValue: String?
    var isPrimaryKey: Bool
}

private enum SQLiteBinding: Sendable {
    case int(Int)
}

enum SQLiteDataExtractionError: LocalizedError, Sendable {
    case open(message: String)
    case prepare(message: String)

    var errorDescription: String? {
        switch self {
        case .open(let message):
            "Could not open SQLite database: \(message)"
        case .prepare(let message):
            "Could not prepare SQLite introspection query: \(message)"
        }
    }
}
