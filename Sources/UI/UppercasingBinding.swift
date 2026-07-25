import SwiftUI

extension Binding where Value == String {
    /// Folds to upper case on the way in, so a field shows what will actually
    /// be logged while it is being typed.
    ///
    /// `.textCase(.uppercase)` only restyles what is drawn — the bound string
    /// keeps whatever case was typed, and the row disagrees with the log until
    /// export normalises it.
    var uppercasing: Binding<String> {
        Binding(
            get: { wrappedValue },
            set: { typed in
                let folded = typed.uppercased()
                // Only write on a real change: assigning an identical string
                // would still publish, and every publish risks moving the
                // insertion point.
                if wrappedValue != folded { wrappedValue = folded }
            }
        )
    }
}
