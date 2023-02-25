//
//  GRDBUndoRedoError.swift
//  GRDBUndoRedo
//
//
//  Created by Perceval Faramaz on 22.02.23.
//

import Foundation

enum GRDBUndoRedoError: Error {
    
    // barrier was called before activation
    case notActive
    
    // activate was called while already active
    case alreadyActive
    
    // undo (respectively redo) attempted while no further undo (resp. redo) actions were available
    case endOfStack
    
    // undo log state has become inconsistent
    case internalInconsistency
    
    case regexError
    
    case foreignKeyReferencedTableNotObserved
}
