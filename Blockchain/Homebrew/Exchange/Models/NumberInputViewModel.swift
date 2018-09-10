//
//  NumberInputViewModel.swift
//  Blockchain
//
//  Created by kevinwu on 8/27/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import Foundation

protocol NumberInputDelegate: class {
    var decimalSeparator: String { get }
    var input: String { get }
    func add(character: String)
    func backspace()
}

// Class used to store the results of user input relayed by the NumberKeypadView.
class NumberInputViewModel: NumberInputDelegate {

    var decimalSeparator: String {
        // Make sure a decimal separator exists
        guard let decimalSeparator = Locale.current.decimalSeparator else {
            Logger.shared.warning("No decimal separator available, using period")
            return "."
        }
        return decimalSeparator
    }
    private let numbers: Set<String> = ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"]
    private let zero = "0"
    private(set) var input: String

    init() {
        input = zero
    }

    init(newInput: String?) {
        input = zero
        // TODO: Sanitize newInput
        input = newInput ?? zero
    }

    func add(character: String) {
        guard numbers.contains(character) || character == decimalSeparator else {
            Logger.shared.error("Invalid character")
            return
        }

        guard character.count == 1 else {
            Logger.shared.error("Character must be a single element")
            return
        }

        // Allow only one decimal separator
        if character == decimalSeparator {
            guard !input.contains(decimalSeparator) else {
                Logger.shared.debug("Decimal already exists")
                return
            }
            // If current input is zero, make it a leading zero and add decimal separator
            guard input != zero else {
                input = zero + decimalSeparator
                return
            }
        }

        // If current input is zero, set to character
        guard input != zero else {
            input = character
            return
        }
        input += character
    }

    func backspace() {
        guard input.count > 1 else {
            input = zero
            return
        }
        input = String(input.dropLast())
    }
}