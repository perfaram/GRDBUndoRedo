//
//  UndoRedo+Helpers.swift
//  
//
//  Created by Perceval Faramaz on 23.02.23.
//

import Foundation
import GRDB

extension GRDBUndoRedo {
    internal func triggerNameForTable(_ table: String, type: String) -> String {
        return "_\(tablePrefix)\(table)_\(type)t"
    }
    
    internal func insertTriggerQuery(table tbl: String) -> String {
        let triggerName = triggerNameForTable(tbl, type: "i")
        
        var sql = "CREATE TEMP TRIGGER \(triggerName) AFTER INSERT ON \(tbl) BEGIN\n"
        sql += "  INSERT INTO \(undologTableName) VALUES(NULL,"
        sql += "'DELETE FROM \(tbl) WHERE rowid='||new.rowid);\nEND;\n"
        
        return sql
    }
    
    internal func updateTriggerQuery(table tbl: String, columns collist: [Row]) -> String {
        let triggerName = triggerNameForTable(tbl, type: "u")
        
        var sql = "CREATE TEMP TRIGGER \(triggerName) AFTER UPDATE ON \(tbl) WHEN("
        var sep = " "
        for col in collist {
            let name: String = col[1]
            sql += "\(sep)(old.\(name) IS NOT new.\(name))"
            sep = " OR "
        }
        sql += ") BEGIN\n"
        sql += "  INSERT INTO \(undologTableName) VALUES(NULL,"
        sql += "'UPDATE \(tbl) "
        sep = "SET "
        for col in collist {
            let name: String = col[1]
            sql += "\(sep)\(name)='||quote(old.\(name))||'"
            sep = ","
        }
        sql += " WHERE rowid='||old.rowid);\nEND"
        
        return sql
    }
    
    internal func deleteTriggerQuery(table tbl: String, columns collist: [Row]) -> String {
        let triggerName = triggerNameForTable(tbl, type: "d")
        
        var sql = "CREATE TEMP TRIGGER \(triggerName) BEFORE DELETE ON \(tbl) BEGIN\n"
        sql += "  INSERT INTO \(undologTableName) VALUES(NULL,"
        sql += "'INSERT INTO \(tbl)(rowid"
        for col in collist {
            let name: String = col[1]
            sql += ",\(name)"
        }
        sql += ") VALUES('||old.rowid||'"
        for col in collist {
            let name: String = col[1]
            sql += ",'||quote(old.\(name))||'"
        }
        sql += ")');\nEND"
        
        return sql
    }
    
    internal func foreignKeysSanityCheck() throws {
        try dbQueue.read { db in
            guard let foreignKeyChecksEnabled = try Bool.fetchOne(db, sql: "PRAGMA foreign_keys") else { return }
            if !foreignKeyChecksEnabled { return }
            
            let foreignKeys = try Row.fetchAll(db, sql: """
            SELECT
                m.name as referencer
                , p."table" as referencee
            FROM
                sqlite_master m
                JOIN pragma_foreign_key_list(m.name) p ON m.name != p."table"
            WHERE m.type = 'table'
            ORDER BY m.name
            ;
            """)
            for foreignKey in foreignKeys {
                let referencer: String = foreignKey["referencer"]
                let referencee: String = foreignKey["referencee"]
                if (observedRecordTypes.contains(referencee) && !(observedRecordTypes.contains(referencer)))
                    || (observedRecordTypes.contains(referencer) && !(observedRecordTypes.contains(referencee))) {
                    throw URError.foreignKeyReferencedTableNotObserved
                }
            }
        }
    }
    
    /// Create change recording triggers for all tables listed.
    ///
    /// Create a temporary table in the database named "undolog".  Create
    /// triggers that fire on any insert, delete, or update of TABLE1, TABLE2, ....
    /// When those triggers fire, insert records in undolog that contain
    /// SQL text for statements that will undo the insert, delete, or update.
    internal func _create_triggers() throws {
        try? dbQueue.write { db in
            try db.execute(sql: "DROP TABLE \(undologTableName)")
        }
        
        try foreignKeysSanityCheck()
        
        try dbQueue.write { db in
            try db.execute(sql: "CREATE TEMP TABLE \(undologTableName)(seq integer primary key, sql text)")
        }
        
        try dbQueue.write { db in
            for tbl in observedRecordTypes {
                let collist = try Row.fetchAll(db, sql: "pragma table_info(\(tbl))")
                
                let insertTrigger = insertTriggerQuery(table: tbl)
                try db.execute(sql: insertTrigger)
                
                let updateTrigger = updateTriggerQuery(table: tbl, columns: collist)
                try db.execute(sql: updateTrigger)
                
                let deleteTrigger = deleteTriggerQuery(table: tbl, columns: collist)
                try db.execute(sql: deleteTrigger)
            }
        }
    }
    
    /// Drop all of the triggers that _create_triggers created.
    internal func _drop_triggers() throws {
        let iudTriggers = ["i", "u", "d"]
        try dbQueue.write { db in
            for tableName in observedRecordTypes {
                let triggerNames = iudTriggers.map { triggerNameForTable(tableName, type: $0) }
                for trigger in triggerNames {
                    try db.execute(sql: "DROP TRIGGER \(trigger);")
                }
            }
            
            try db.execute(sql: "DROP TABLE \(undologTableName)")
        }
    }
    
    /// Record the starting conditions of an undo interval.
    internal func _start_interval() throws {
        _undoState.firstLog = try self.dbQueue.read { db in
            guard let firstLog =
                    try Int.fetchOne(db,
                                     sql: "SELECT coalesce(max(seq),0)+1 FROM \(undologTableName)")
            else {
                throw URError.internalInconsistency
            }
            return firstLog
        }
    }
}
