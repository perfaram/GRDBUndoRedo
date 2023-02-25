//
//  UndoRedoManager.swift
//  GRDBUndoRedo
//
//  Created by Perceval Faramaz on 22.02.23.
//
//  Mostly a translation of the Tcl example code at https://www.sqlite.org/undoredo.html (public domain)
//  With great help drawn from Alain Martin's translation
//  to C++ and Python, at https://github.com/McMartin/sqlite-undoredo
//
//  Expanded features:
//  * Non-naive update trigger
//  * Foreign key support
//  * Support concurrent instances observing different areas of a database
//

import Foundation
import GRDB

/// An automated undo-redo manager based on SQLite triggers.
///
/// The methods on this class must never be called from within a GRDB read/write block.
/// Although, GRDB checks for such cases and will raise, so no deadlock will happen.
public class UndoRedoManager {
    typealias URError = GRDBUndoRedoError
    
    public enum Action {
        case undo
        case redo
    }
    
    internal var dbQueue: DatabaseQueue
    internal var _undoState: UndoState = UndoState()
    internal let tablePrefix: String
    internal let undologTableName: String
    
    internal let observedRecordTypes: Set<String>
    
    /// Regenerates the triggers and "listens" to changes again.
    public func reactivate() throws {
        if _undoState.active {
            return
        }
        
        try _create_triggers()
        _undoState.undoStack = []
        _undoState.redoStack = []
        _undoState.active = true
        _undoState.freeze = -1
        try self._start_interval()
    }
    
    /// Halt the undo/redo system and delete the undo/redo stacks.
    public func deactivate() throws {
        if !_undoState.active {
            return
        }
        try _drop_triggers()
        _undoState.undoStack = []
        _undoState.redoStack = []
        _undoState.active = false
        _undoState.freeze = -1
    }
    
    /// Initializes the undo/redo system. 
    ///
    /// Arguments should be one or more database tables (in the database associated
    /// with the handle "db") whose changes are to be recorded for undo/redo purposes.
    public init(recordTypes: TableRecord.Type..., db: DatabaseQueue, tablePrefix: String = "") throws {
        self.dbQueue = db
        let prefix = tablePrefix == "" ? "" : "\(tablePrefix)_"
        self.tablePrefix = prefix
        self.undologTableName = "\(prefix)undolog"
        self.observedRecordTypes = Set(recordTypes.map { $0.databaseTableName })
        
        try reactivate()
    }
    
    deinit {
        try? deactivate()
    }

    /// Do a single step of undo or redo.
    public func perform(_ action: Action) throws {
        let isUndo = action == .undo
        var v1 = isUndo ? _undoState.undoStack : _undoState.redoStack
        var v2 = isUndo ? _undoState.redoStack : _undoState.undoStack
        
        guard let op = v1.popLast() else {
            throw URError.endOfStack
        }
        
        _undoState.firstLog = try dbQueue.write { db in
            let sqllist = try String.fetchAll(db,
                             sql: "SELECT sql FROM \(undologTableName) WHERE seq>=:begin AND seq<=:end ORDER BY seq DESC",
                             arguments: ["begin": op.begin, "end": op.end])
            try db.execute(
                sql: "DELETE FROM \(undologTableName) WHERE seq>=:begin AND seq<=:end",
                arguments: ["begin": op.begin, "end": op.end])
            
            guard let firstLog = try Int.fetchOne(db, sql: "SELECT coalesce(max(seq),0)+1 FROM \(undologTableName)") else {
                throw URError.internalInconsistency
            }
            
            // Defers all foreign key verification to the end of the transactions
            // As the undo/redo steps might not be executed in an order that preserves
            // these constraints.
            try db.execute(sql: "PRAGMA defer_foreign_keys = TRUE;")
            for sql in sqllist {
                try db.execute(sql: sql)
            }
            return firstLog
        }
        //self.reload_all()
        
        let end = try self.dbQueue.read { db in
            guard let end = try Int.fetchOne(db, sql: "SELECT coalesce(max(seq),0) as end FROM \(undologTableName)") else {
                throw URError.internalInconsistency
            }
            return end
        }
        
        let begin = _undoState.firstLog
        v2.append(UndoRange(begin: begin, end: end))
        
        if isUndo {
            _undoState.undoStack = v1
            _undoState.redoStack = v2
        }
        else {
            _undoState.undoStack = v2
            _undoState.redoStack = v1
        }
        
        try self._start_interval()
    }
    
    /// Stop accepting database changes into the undo stack.
    ///
    /// From the point when this routine is called up until the next unfreeze,
    /// new database changes are rejected from the undo stack.
    public func freeze() throws {
        guard _undoState.active else {
            throw URError.notActive
        }
        
        if _undoState.freeze >= 0 {
            return
        }

        try self.dbQueue.read { db in
            if let row = try Row.fetchOne(db, sql: "SELECT coalesce(max(seq),0) as freeze FROM \(undologTableName)") {
                _undoState.freeze = row["freeze"]
            }
        }
    }
    
    /// Begin accepting undo actions again.
    public func unfreeze() throws {
        guard _undoState.active else {
            throw URError.notActive
        }
        
        if _undoState.freeze < 0 {
            return
        }
        try self.dbQueue.write { db in
            try db.execute(
                sql: "DELETE FROM \(undologTableName) WHERE seq>:freeze",
                arguments: ["freeze": _undoState.freeze])
        }
        
        _undoState.freeze = -1
    }
    
    /// Create an undo barrier right now.
    public func barrier() throws -> Bool {
        guard _undoState.active else {
            throw URError.notActive
        }
        
        var end: Int = try self.dbQueue.read { db in
            guard let end = try Int.fetchOne(db, sql: "SELECT coalesce(max(seq),0) FROM \(undologTableName)") else {
                throw URError.internalInconsistency
            }
            return end
        }
        
        if (_undoState.freeze >= 0) && (end > _undoState.freeze) {
            end = _undoState.freeze
        }
        
        let begin = _undoState.firstLog
        try self._start_interval()
        
        if begin == _undoState.firstLog {
            return false
        }
        _undoState.undoStack.append(UndoRange(begin: begin, end: end))
        _undoState.redoStack = []
        return true
    }
}

extension UndoRedoManager {
    public var isActive: Bool {
        get {
            return _undoState.active
        }
    }
    
    public var isFrozen: Bool {
        get {
            return _undoState.freeze >= 0
        }
    }
    
    public var canUndo: Bool {
        get {
            return !_undoState.undoStack.isEmpty
        }
    }
    
    public var canRedo: Bool {
        get {
            return !_undoState.redoStack.isEmpty
        }
    }
}
