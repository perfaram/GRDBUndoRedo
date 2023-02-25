# GRDBUndoRedo

This package provides undo-redo features for projects using [GRDB](https://github.com/groue/GRDB.swift). The undo-redo log is generated and managed through SQLite triggers. 

## Installation
Through Swift Package Manager.

## Usage
Let's say you have this GRDB record:
```swift
struct Book: Identifiable, Equatable, Hashable {
    var id: Int64? = nil
    var title: String
    var year: Int
    var author: String
}

/// And its migration:
migrator.registerMigration("createRecords") { db in
    try db.create(table: "books") { t in
        t.autoIncrementedPrimaryKey("id")
        t.column("title", .text).notNull().unique()
        t.column("year", .integer).notNull()
        t.column("author", .text).notNull()
    }
}
```

Then, we advise to use the [database manager](https://github.com/groue/GRDB.swift/blob/master/Documentation/GoodPracticesForDesigningRecordTypes.md#how-to-design-database-managers) to hold the GRDBUndoRedo instance.
```swift
class DatabaseManager {
    private let dbQueue: DatabaseQueue
    private let undoRedo: GRDBUndoRedo
    
    init(dbQueue: DatabaseQueue) throws {
        self.dbQueue = dbQueue
        self.undoRedo = try GRDBUndoRedo(recordTypes: Book.self, db: /*your GRDB database queue or pool*/)
    }
```

You can handle more than one table / record type: `self.undoRedo = try GRDBUndoRedo(recordTypes: Book.self, Author.self, Editor.self, db: ...)`. Together, the tables watched by GRDBUndoRedo form a "undo-redo scope". 
If the tables included in the scope have foreign key relationships to each other, see "Foreign Keys" below. 

### Edit barriers
After each "step" (an action in your application), call `try undoRedo.barrier()`. It can then be undone by calling `try undoRedo.perform(.undo)` (then, `.redo`). 
```
extension DatabaseManager {
    /// Saves (inserts or updates) a book. When the method returns, the
    /// book is present in the database, and its id is not nil.
    func saveBook(_ player: inout Book) throws {
        /*validate that the book title, year, author*/
        
        // save to database
        try dbWriter.write { db in
            try book.save(db)
        }
        
        // mark an atomic step, that can be un-done then possibly re-done
        try self.undoRedo.barrier()
    }
}
```

A step can include more than one database transaction. Be careful, that all changes between two calls to `.barrier()` will be grouped in one step.

### Freezing
If your database can receive changes without user action, e.g. through background network calls, be careful not to let the user accidentally undo these! You can tell `GRDBUndoRedo` to stop recording database changes via `.freeze()` / then `.unfreeze()`. However: this library has no understanding of your application logic, so be careful regarding data consistency.

### Foreign keys
If foreign keys enforcement is enabled, `GRDBUndoRedo.init` will ensure that no table, that is related through foreign keys to tables included in the undo-redo scope, are omitted; and will raise in such a case. If a database operation has cascade effects, all the changes will be included in the same step, and thus will reverted together on undo. 

### Concurrent instances
It is possible to supply a prefix to `GRDBUndoRedo.init`, so that multiple instances can handle undo-redo for **non-overlapping scopes** in the same database. Having overlapping scopes will result in unpredictable consequences and possibly inconsistent data. 

## Acknowledgments
It is largely based on the [example code available on the SQLite website](https://www.sqlite.org/undoredo.html.).
[This translation](https://github.com/McMartin/sqlite-undoredo) to C++ and Python proved useful in understanding and translating the code to Swift. 
