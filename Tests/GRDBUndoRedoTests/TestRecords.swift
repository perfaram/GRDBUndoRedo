//
//  TestRecords.swift
//  
//
//  Created by Perceval Faramaz on 24.02.23.
//

import Foundation
import GRDB

struct Tbl1: Equatable, Hashable {
    var a: Int
}

extension Tbl1: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "tbl1"
    
    // Define database columns from CodingKeys
    fileprivate enum Columns {
        static let a = Column(CodingKeys.a)
    }
}

struct Tbl2: Equatable, Hashable {
    var b: Int
}

extension Tbl2: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "tbl2"
    
    // Define database columns from CodingKeys
    fileprivate enum Columns {
        static let b = Column(CodingKeys.b)
    }
}

// MARK: - Tables with foreign key relationships

struct RTbl1: Identifiable, Equatable, Hashable {
    var id: Int64? = nil
    var val1: String
}

extension RTbl1: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "rtbl1"
    
    // Define database columns from CodingKeys
    fileprivate enum Columns {
        static let id = Column(CodingKeys.id)
        static let val1 = Column(CodingKeys.val1)
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        self.id = inserted.rowID
    }
}

struct RTbl2: Identifiable, Equatable, Hashable {
    var id: Int64? = nil
    var relation: Int64
}

extension RTbl2: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "rtbl2"
    static let rtbl1 = belongsTo(RTbl1.self, key: "relation")
    
    // Define database columns from CodingKeys
    fileprivate enum Columns {
        static let id = Column(CodingKeys.id)
        static let relation = Column(CodingKeys.relation)
    }
    
    mutating func didInsert(_ inserted: InsertionSuccess) {
        self.id = inserted.rowID
    }
}
