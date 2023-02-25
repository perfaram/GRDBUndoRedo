import XCTest
@testable import GRDBUndoRedo
import GRDB

final class UndoRedoManagerTests: XCTestCase {
    var dbQueue: DatabaseQueue!
    var undoRedo: UndoRedoManager!
    
    private func insertDummies(_ items: Array<MutablePersistableRecord>) throws {
        try dbQueue.write { db in
            for var newItem in items {
                try newItem.insert(db)
            }
        }
    }
    
    
    func testActivateOneTable() throws {
        var undoState = UndoState()
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        XCTAssertEqual(undoRedo._undoState.firstLog, 1)
        
        let iudTriggers = ["i", "u", "d"]
        let triggerNames = iudTriggers.map { undoRedo.triggerNameForTable(Tbl1.databaseTableName, type: $0) }
        try dbQueue.read { db in
            for name in triggerNames {
                XCTAssertTrue(try db.triggerExists(name))
            }
        }
        
        undoState.active = true
        undoState.freeze = -1
        XCTAssertEqual(undoState, undoRedo._undoState)
    }
    
    func testActivateSeveralTables() throws {
        var undoState = UndoState()
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, Tbl2.self, db: dbQueue)
        
        let iudTriggers = ["i", "u", "d"]
        var triggerNames = iudTriggers.map { undoRedo.triggerNameForTable(Tbl1.databaseTableName, type: $0) }
        triggerNames += iudTriggers.map { undoRedo.triggerNameForTable(Tbl2.databaseTableName, type: $0) }
        try dbQueue.read { db in
            for name in triggerNames {
                XCTAssertTrue(try db.triggerExists(name))
            }
        }
        
        undoState.active = true
        undoState.freeze = -1
        XCTAssertEqual(undoState, undoRedo._undoState)
    }
    
    func testReactivateWhileActive() throws {
        undoRedo = try UndoRedoManager(db: dbQueue)
        let undoState = undoRedo._undoState
        XCTAssertEqual(undoState.active, true)
        
        try undoRedo.reactivate()
        XCTAssertEqual(undoState, undoRedo._undoState)
    }
    
    func testDeactivate() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        var state = undoRedo._undoState
        
        try undoRedo.deactivate()
        
        let iudTriggers = ["i", "u", "d"]
        let triggerNames = iudTriggers.map { undoRedo.triggerNameForTable(Tbl1.databaseTableName, type: $0) }
        
        try dbQueue.read { db in
            for name in triggerNames {
                XCTAssertFalse(try db.triggerExists(name))
            }
        }
        
        state.active = false
        state.freeze = -1
        XCTAssertEqual(state, undoRedo._undoState)
    }
    
    func testActiveGetterConsistency() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        
        XCTAssertEqual(undoRedo.isActive, undoRedo._undoState.active)
        try undoRedo.deactivate()
        XCTAssertEqual(undoRedo.isActive, undoRedo._undoState.active)
    }
    
    func testFreeze() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        XCTAssertEqual(undoRedo._undoState.freeze, -1)
        let newItems = [Tbl1(a: 4), Tbl1(a: 8)]
        try insertDummies(newItems)
        
        XCTAssertTrue(try undoRedo.barrier())
        try undoRedo.freeze()
        XCTAssertEqual(undoRedo._undoState.freeze, 2)
    }
    
    func testFreezeWhileFrozen() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        XCTAssertEqual(undoRedo._undoState.freeze, -1)
        
        try undoRedo.freeze()
        let state = undoRedo._undoState
        XCTAssertEqual(undoRedo._undoState.freeze, 0)
        
        try undoRedo.freeze()
        XCTAssertEqual(state, undoRedo._undoState)
    }
    
    func testFreezeWhileNotActive() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        try undoRedo.deactivate()
        let state = undoRedo._undoState
        
        XCTAssertThrowsError(try undoRedo.freeze()) { error in
            XCTAssertEqual(error as! GRDBUndoRedoError, GRDBUndoRedoError.notActive)
        }
        XCTAssertEqual(state, undoRedo._undoState)
    }
    
    func testUnfreeze() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        XCTAssertEqual(undoRedo._undoState.freeze, -1)
        
        let newItems = [Tbl1(a: 15), Tbl1(a: 16)]
        try insertDummies(newItems)
        _ = try undoRedo.barrier()
        
        try undoRedo.freeze()
        
        let moreItems = [Tbl1(a: 23), Tbl1(a: 42)]
        try insertDummies(moreItems)
        XCTAssertTrue(try undoRedo.barrier())
        
        let logCount = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(undoRedo.undologTableName)")
        }
        XCTAssertEqual(logCount, 4)
        
        try undoRedo.unfreeze()
        let newLogCount = try dbQueue.read { db in
            try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM \(undoRedo.undologTableName)")
        }
        XCTAssertEqual(newLogCount, 2)
        
        XCTAssertEqual(undoRedo._undoState.freeze, -1)
    }
    
    func testUnfreezeWhileNotActive() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        try undoRedo.deactivate()
        let state = undoRedo._undoState
        
        XCTAssertThrowsError(try undoRedo.unfreeze()) { error in
            XCTAssertEqual(error as! GRDBUndoRedoError, GRDBUndoRedoError.notActive)
        }
        XCTAssertEqual(state, undoRedo._undoState)
        
        try undoRedo.reactivate()
        try undoRedo.freeze()
        XCTAssertEqual(undoRedo.isFrozen, true)
    }
    
    func testFrozenGetterConsistency() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        XCTAssertEqual(undoRedo.isFrozen, false)
        try undoRedo.freeze()
        XCTAssertEqual(undoRedo.isFrozen, true)
    }
    
    func testUnfreezeWhileNotFrozen() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        XCTAssertEqual(undoRedo.isFrozen, false)
        
        let state = undoRedo._undoState
        try undoRedo.unfreeze()
        XCTAssertEqual(state, undoRedo._undoState)
    }
    
    func testBarrier() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        
        try insertDummies([Tbl1(a: 66)])
        XCTAssertTrue(try undoRedo.barrier())
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 1)])
        
        try insertDummies([Tbl1(a: 69)])
        XCTAssertTrue(try undoRedo.barrier())
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 1), UndoRange(begin: 2, end: 2)])
    }
    
    func testBarrierBulkChanges() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        
        let newItems = [Tbl1(a: 404), Tbl1(a: 420)]
        try insertDummies(newItems)
        XCTAssertTrue(try undoRedo.barrier())
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 2)])
    }
    
    func testBarrierWhileNotActive() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        try undoRedo.deactivate()
        XCTAssertThrowsError(try undoRedo.barrier()) { error in
            XCTAssertEqual(error as! GRDBUndoRedoError, GRDBUndoRedoError.notActive)
        }
        try undoRedo.reactivate()
        XCTAssertFalse(try undoRedo.barrier())
    }
    
    func testBarrierWhileFrozen() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        try insertDummies([Tbl1(a: 23)])
        XCTAssertTrue(try undoRedo.barrier())
        
        try undoRedo.freeze()
        try insertDummies([Tbl1(a: 42)])
        
        XCTAssertTrue(try undoRedo.barrier())
        
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 1), UndoRange(begin: 2, end: 1)])
    }
    
    func testBarrierAfterNoChanges() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        
        try insertDummies([Tbl1(a: 23)])
        XCTAssertTrue(try undoRedo.barrier())
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 1)])
        
        XCTAssertFalse(try undoRedo.barrier())
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 1)])
    }
    
    func testUndoNoChanges() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        XCTAssertThrowsError(try undoRedo.perform(.undo)) { error in
            XCTAssertEqual(error as! GRDBUndoRedoError, GRDBUndoRedoError.endOfStack)
        }
    }
    
    func testCanUndoGetterConsistency() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        XCTAssertFalse(undoRedo.canUndo)
        
        let newItems = [Tbl1(a: 404)]
        try insertDummies(newItems)
        XCTAssertTrue(try undoRedo.barrier())
        XCTAssertTrue(undoRedo.canUndo)
    }
    
    func testUndoInsertOne() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        
        let newItems = [Tbl1(a: 404)]
        try insertDummies(newItems)
        XCTAssertTrue(try undoRedo.barrier())
        try dbQueue.read { db in
            let items = try Tbl1.fetchAll(db)
            XCTAssertEqual(items.count, newItems.count)
        }
        
        XCTAssertEqual(undoRedo._undoState.firstLog, 1+newItems.count)
        XCTAssertEqual(undoRedo._undoState.redoStack, [])
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 1)])
        try undoRedo.perform(.undo)
        XCTAssertEqual(undoRedo._undoState.undoStack, [])
        XCTAssertEqual(undoRedo._undoState.redoStack, [UndoRange(begin: 1, end: 1)])
        XCTAssertEqual(undoRedo._undoState.firstLog, 1+newItems.count)
        
        try dbQueue.read { db in
            let items = try Tbl1.fetchAll(db)
            XCTAssertEqual(items.count, 0)
        }
    }
    
    func testUndoInsertBulk() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        
        let newItems = [Tbl1(a: 404), Tbl1(a: 420)]
        try insertDummies(newItems)
        XCTAssertTrue(try undoRedo.barrier())
        try dbQueue.read { db in
            let items = try Tbl1.fetchAll(db)
            XCTAssertEqual(items.count, newItems.count)
        }
        
        XCTAssertEqual(undoRedo._undoState.firstLog, 1+newItems.count)
        XCTAssertEqual(undoRedo._undoState.redoStack, [])
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 2)])
        try undoRedo.perform(.undo)
        XCTAssertEqual(undoRedo._undoState.undoStack, [])
        XCTAssertEqual(undoRedo._undoState.redoStack, [UndoRange(begin: 1, end: 2)])
        XCTAssertEqual(undoRedo._undoState.firstLog, 1+newItems.count)
        
        try dbQueue.read { db in
            let items = try Tbl1.fetchAll(db)
            XCTAssertEqual(items.count, 0)
        }
    }
    
    func testUndoUpdate() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        
        let newItem = Tbl1(a: 1)
        try insertDummies([newItem])
        _ = try undoRedo.barrier()
        
        let new_aValue = 2
        try dbQueue.write({ db in
            try db.execute(sql: "UPDATE \(Tbl1.databaseTableName) SET a=? WHERE a=?", arguments: [new_aValue, newItem.a])
        })
        XCTAssertTrue(try undoRedo.barrier())
        
        let items = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        XCTAssertEqual(items, [Tbl1(a: new_aValue)])
        
        try undoRedo.perform(.undo)
        
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 1)])
        XCTAssertEqual(undoRedo._undoState.redoStack, [UndoRange(begin: 2, end: 2)])
        XCTAssertEqual(undoRedo._undoState.firstLog, 3)
        
        let itemsAfterUndo = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        XCTAssertEqual(itemsAfterUndo, [newItem])
    }
    
    func testNonNaiveUpdateTrigger() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        
        let aValue = 2
        let newItem = Tbl1(a: aValue)
        try insertDummies([newItem])
        _ = try undoRedo.barrier()
        
        try dbQueue.write({ db in
            try db.execute(sql: "UPDATE \(Tbl1.databaseTableName) SET a=? WHERE a=?", arguments: [aValue, aValue])
        })
        XCTAssertFalse(try undoRedo.barrier())
    }
    
    func testUndoDelete() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        
        let newItem = Tbl1(a: 1)
        try insertDummies([newItem])
        _ = try undoRedo.barrier()
        
        try dbQueue.write({ db in
            try db.execute(sql: "DELETE FROM \(Tbl1.databaseTableName) WHERE a=?", arguments: [newItem.a])
        })
        XCTAssertTrue(try undoRedo.barrier())
        
        let items = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        XCTAssertTrue(items.isEmpty)
        
        try undoRedo.perform(.undo)
        
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 1)])
        XCTAssertEqual(undoRedo._undoState.redoStack, [UndoRange(begin: 2, end: 2)])
        XCTAssertEqual(undoRedo._undoState.firstLog, 3)
        
        let itemsAfterUndo = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        XCTAssertEqual(itemsAfterUndo, [newItem])
    }
    
    func testUndoSeveralChanges() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        
        let newItems = [Tbl1(a: 23), Tbl1(a: 42)]
        try insertDummies(newItems)
        _ = try undoRedo.barrier()
        
        try insertDummies([Tbl1(a: 69)])
        let new_aValue = 22
        try dbQueue.write({ db in
            try db.execute(sql: "UPDATE \(Tbl1.databaseTableName) SET a=? WHERE a=?", arguments: [new_aValue, newItems[0].a])
        })
        try dbQueue.write({ db in
            try db.execute(sql: "DELETE FROM \(Tbl1.databaseTableName) WHERE a=?", arguments: [newItems[1].a])
        })
        XCTAssertTrue(try undoRedo.barrier())
        
        let items = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        let existing_aValues = Set(items.map { $0.a })
        let theoretical_aValues = Set([22, 69])
        XCTAssertEqual(existing_aValues, theoretical_aValues)
        
        try undoRedo.perform(.undo)
        
        let itemsAfterUndo = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        XCTAssertEqual(Set(itemsAfterUndo), Set(newItems))
        
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 2)])
        XCTAssertEqual(undoRedo._undoState.redoStack, [UndoRange(begin: 3, end: 5)])
        XCTAssertEqual(undoRedo._undoState.firstLog, 6)
    }
    
    func testRedoNoChanges() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        XCTAssertThrowsError(try undoRedo.perform(.redo)) { error in
            XCTAssertEqual(error as! GRDBUndoRedoError, GRDBUndoRedoError.endOfStack)
        }
    }
    
    func testCanRedoGetterConsistency() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        XCTAssertFalse(undoRedo.canRedo)
        
        let newItems = [Tbl1(a: 404)]
        try insertDummies(newItems)
        XCTAssertTrue(try undoRedo.barrier())
        XCTAssertFalse(undoRedo.canRedo)
        
        try undoRedo.perform(.undo)
        XCTAssertTrue(undoRedo.canRedo)
        try undoRedo.perform(.redo)
        XCTAssertFalse(undoRedo.canRedo)
    }
    
    func testRedoInsert() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        let newItems = [Tbl1(a: 23)]
        try insertDummies(newItems)
        _ = try undoRedo.barrier()
        
        try undoRedo.perform(.undo)
        let itemsAfterUndo = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        XCTAssertTrue(itemsAfterUndo.isEmpty)
        
        try undoRedo.perform(.redo)
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 1)])
        XCTAssertEqual(undoRedo._undoState.redoStack, [])
        XCTAssertEqual(undoRedo._undoState.firstLog, 2)
        
        let itemsAfterRedo = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        XCTAssertEqual(itemsAfterRedo, newItems)
    }
    
    func testRedoUpdate() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        let newItems = [Tbl1(a: 23)]
        try insertDummies(newItems)
        _ = try undoRedo.barrier()
        
        let new_aValue = 42
        try dbQueue.write({ db in
            try db.execute(sql: "UPDATE \(Tbl1.databaseTableName) SET a=? WHERE a=?", arguments: [new_aValue, newItems[0].a])
        })
        XCTAssertTrue(try undoRedo.barrier())
        
        try undoRedo.perform(.undo)
        let itemsAfterUndo = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        XCTAssertEqual(itemsAfterUndo, newItems)
        
        try undoRedo.perform(.redo)
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 1), UndoRange(begin: 2, end: 2)])
        XCTAssertEqual(undoRedo._undoState.redoStack, [])
        XCTAssertEqual(undoRedo._undoState.firstLog, 3)
        
        let itemsAfterRedo = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        XCTAssertEqual(itemsAfterRedo, [Tbl1(a: new_aValue)])
    }
    
    func testRedoDelete() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        let newItems = [Tbl1(a: 23)]
        try insertDummies(newItems)
        _ = try undoRedo.barrier()
        
        try dbQueue.write({ db in
            try db.execute(sql: "DELETE FROM \(Tbl1.databaseTableName) WHERE a=?", arguments: [newItems[0].a])
        })
        XCTAssertTrue(try undoRedo.barrier())
        
        let items = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        XCTAssertTrue(items.isEmpty)
        
        try undoRedo.perform(.undo)
        let itemsAfterUndo = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        XCTAssertEqual(itemsAfterUndo, newItems)
        
        try undoRedo.perform(.redo)
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 1), UndoRange(begin: 2, end: 2)])
        XCTAssertEqual(undoRedo._undoState.redoStack, [])
        XCTAssertEqual(undoRedo._undoState.firstLog, 3)
        
        let itemsAfterRedo = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        XCTAssertEqual(itemsAfterRedo, [])
    }
    
    func testRedoSeveralChanges() throws {
        undoRedo = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue)
        
        let newItems = [Tbl1(a: 23), Tbl1(a: 42)]
        try insertDummies(newItems)
        _ = try undoRedo.barrier()
        
        try insertDummies([Tbl1(a: 69)])
        let new_aValue = 22
        try dbQueue.write({ db in
            try db.execute(sql: "UPDATE \(Tbl1.databaseTableName) SET a=? WHERE a=?", arguments: [new_aValue, newItems[0].a])
        })
        try dbQueue.write({ db in
            try db.execute(sql: "DELETE FROM \(Tbl1.databaseTableName) WHERE a=?", arguments: [newItems[1].a])
        })
        XCTAssertTrue(try undoRedo.barrier())
        
        let items = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        let existing_aValues = Set(items.map { $0.a })
        let theoretical_aValues = Set([22, 69])
        XCTAssertEqual(existing_aValues, theoretical_aValues)
        
        try undoRedo.perform(.undo)
        
        let itemsAfterUndo = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        XCTAssertEqual(Set(itemsAfterUndo), Set(newItems))
        
        try undoRedo.perform(.redo)
        
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 2), UndoRange(begin: 3, end: 5)])
        XCTAssertEqual(undoRedo._undoState.redoStack, [])
        XCTAssertEqual(undoRedo._undoState.firstLog, 6)
        
        let itemsAfterRedo = try dbQueue.read({ db in
            return try Tbl1.fetchAll(db)
        })
        let existing_aValuesAfterRedo = Set(itemsAfterRedo.map { $0.a })
        XCTAssertEqual(existing_aValuesAfterRedo, theoretical_aValues)
    }
    
    func testForeignKeysObservedTablesSanityCheck() throws {
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = OFF;")
        }
        
        XCTAssertNoThrow(try UndoRedoManager(recordTypes: RTbl1.self, db: dbQueue))
        XCTAssertNoThrow(try UndoRedoManager(recordTypes: RTbl2.self, db: dbQueue))
        
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
        }
        
        XCTAssertThrowsError(try UndoRedoManager(recordTypes: RTbl1.self, db: dbQueue)) { error in
            XCTAssertEqual(error as! GRDBUndoRedoError, GRDBUndoRedoError.foreignKeyReferencedTableNotObserved)
        }
        
        XCTAssertThrowsError(try UndoRedoManager(recordTypes: RTbl2.self, db: dbQueue)) { error in
            XCTAssertEqual(error as! GRDBUndoRedoError, GRDBUndoRedoError.foreignKeyReferencedTableNotObserved)
        }
    }
    
    func testForeignKeysOnDelete() throws {
        try dbQueue.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON;")
        }
        undoRedo = try UndoRedoManager(recordTypes: RTbl1.self, RTbl2.self, db: dbQueue)
        
        var parent = RTbl1(val1: "A")
        try dbQueue.write({ db in
            try parent.insert(db)
        })
        
        var child = RTbl2(relation: parent.id!)
        try dbQueue.write({ db in
            try child.insert(db)
        })
        
        XCTAssertTrue(try undoRedo.barrier())
        
        let deletionSuccess = try dbQueue.write({ db in
            try parent.delete(db)
        })
        XCTAssertTrue(deletionSuccess)
        XCTAssertTrue(try undoRedo.barrier())
        
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 2), UndoRange(begin: 3, end: 4)])
        XCTAssertEqual(undoRedo._undoState.redoStack, [])
        XCTAssertEqual(undoRedo._undoState.firstLog, 5)
        
        let allChildren = try dbQueue.read({ db in
            try RTbl2.fetchAll(db)
        })
        XCTAssertTrue(allChildren.isEmpty)
        
        try undoRedo.perform(.undo)
        XCTAssertEqual(undoRedo._undoState.undoStack, [UndoRange(begin: 1, end: 2)])
        XCTAssertEqual(undoRedo._undoState.redoStack, [UndoRange(begin: 3, end: 4)])
        XCTAssertEqual(undoRedo._undoState.firstLog, 5)
        
        let allChildrenAfterUndo = try dbQueue.read({ db in
            try RTbl2.fetchAll(db)
        })
        XCTAssertEqual(allChildrenAfterUndo.count, 1)
    }
    
    func testConcurrentInstances() throws {
        let undoRedoA = try UndoRedoManager(recordTypes: Tbl1.self, db: dbQueue, tablePrefix: "URA")
        let undoRedoB = try UndoRedoManager(recordTypes: Tbl2.self, db: dbQueue, tablePrefix: "URB")
        
        let itemForA = Tbl1(a: 11)
        try insertDummies([itemForA])
        XCTAssertTrue(try undoRedoA.barrier())
        XCTAssertEqual(undoRedoA._undoState.undoStack, [UndoRange(begin: 1, end: 1)])
        
        try insertDummies([Tbl2(b: 22)])
        XCTAssertTrue(try undoRedoB.barrier())
        XCTAssertEqual(undoRedoB._undoState.undoStack, [UndoRange(begin: 1, end: 1)])
        
        try dbQueue.write({ db in
            try db.execute(sql: "DELETE FROM \(Tbl1.databaseTableName) WHERE a=?", arguments: [itemForA.a])
        })
        XCTAssertTrue(try undoRedoA.barrier())
        XCTAssertFalse(try undoRedoB.barrier())
    }
    
    override func setUpWithError() throws {
        dbQueue = try DatabaseQueue()
        
        try dbQueue.write { db in
            try db.create(table: "tbl1") { t in
                t.column("a", .integer)
            }
            try db.create(table: "tbl2") { t in
                t.column("b", .integer)
            }
            
            try db.create(table: "rtbl1") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("val1", .text).notNull()
            }
            try db.create(table: "rtbl2") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("relation", .integer)
                    .references("rtbl1",
                                column: "id",
                                onDelete: .cascade,
                                onUpdate: .none)
            }
        }
    }
}
