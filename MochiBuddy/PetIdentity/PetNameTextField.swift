//
//  PetNameTextField.swift
//  MochiBuddy
//
//  The one field for naming/renaming the pet, shared by the onboarding
//  naming beat and the You-tab rename sheet. UIKit-backed because the live
//  16-grapheme cap must count *committed* graphemes only: SwiftUI's
//  TextField can't see marked (in-composition) text, and truncating a CJK
//  composition mid-flight corrupts it. The accept/reject decision itself
//  is the pure PetNameFieldPolicy.
//

import SwiftUI
import UIKit

struct PetNameTextField: UIViewRepresentable {

    @Binding var text: String
    var placeholder = PetNameSanitizer.defaultName
    var font: UIFont = UIFont(name: "Nunito", size: 15) ?? .systemFont(ofSize: 15, weight: .bold)
    var textColor: UIColor?
    var onSubmit: (() -> Void)?
    /// FocusState can't observe a UIKit field - hosts get begin/end
    /// editing through here for focus-styled borders.
    var onEditingChanged: ((Bool) -> Void)?

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.font = font
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.autocapitalizationType = .words
        field.returnKeyType = .done
        field.delegate = context.coordinator
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(
            context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged
        )
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.text != text, field.markedTextRange == nil {
            field.text = text
        }
        if let textColor {
            field.textColor = textColor
        }
        field.placeholder = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PetNameTextField

        init(parent: PetNameTextField) {
            self.parent = parent
        }

        func textField(
            _ field: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let current = field.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return true }
            let proposed = current.replacingCharacters(in: swiftRange, with: string)
            return PetNameFieldPolicy.acceptsChange(
                proposed: proposed,
                hasMarkedText: field.markedTextRange != nil
            )
        }

        @objc func editingChanged(_ field: UITextField) {
            // Marked text stays out of the binding until composition
            // commits; the cap then applies to what actually committed.
            guard field.markedTextRange == nil else { return }
            var committed = field.text ?? ""
            if committed.count > PetNameSanitizer.maxGraphemes {
                committed = String(committed.prefix(PetNameSanitizer.maxGraphemes))
                field.text = committed
            }
            parent.text = committed
        }

        func textFieldShouldReturn(_ field: UITextField) -> Bool {
            field.resignFirstResponder()
            parent.onSubmit?()
            return true
        }

        func textFieldDidBeginEditing(_ field: UITextField) {
            parent.onEditingChanged?(true)
        }

        func textFieldDidEndEditing(_ field: UITextField) {
            parent.onEditingChanged?(false)
        }
    }
}
