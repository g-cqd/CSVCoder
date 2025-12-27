//
//  Plugin.swift
//  CSVCoder
//
//  Compiler plugin entry point for CSVCoder macros.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

@main
struct CSVCoderMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        CSVIndexedMacro.self,
        CSVColumnMacro.self
    ]
}
