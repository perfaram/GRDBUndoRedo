//
//  File.swift
//  
//
//  Created by Perceval Faramaz on 22.02.23.
//

import Foundation

internal struct UndoRange: Equatable {
    let begin: Int
    let end: Int
}

internal struct UndoState: Equatable {
    var active: Bool = false
    var undoStack: [UndoRange] = []
    var redoStack: [UndoRange] = []
    var pending: [Int] = []
    var firstLog: Int = 1
    //var startState: [Int] = []
    
    var freeze: Int = -1
}
