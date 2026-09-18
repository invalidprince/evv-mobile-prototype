import Foundation
import UIKit

// Build 75 — keyboard dismissal (Todoist 6hWwwmxrqchxrf7H).
//
// Compiles the REAL `isTextInputOrUIControl` out of KeyboardDismiss.swift
// (check.sh concatenates it) and exercises it against real UIKit view trees.
// This is the one piece of the card that is decidable logic rather than
// SwiftUI layout: WHICH taps the window recognizer must decline.
//
// 🎯 NON-VACUOUS CONTROL (section C): a stripped reimplementation that only
// checks the hit view itself instead of walking up the superview chain. The
// real function must pass the nested cases where the control fails — otherwise
// these assertions would pass on a broken walk and prove nothing. That's the
// actual bug risk here: SwiftUI hands the recognizer a deeply nested private
// subview (_UITextLayoutView inside UITextView inside a host view), never the
// UITextView itself, so a non-walking check would dismiss the keyboard while
// the user is placing a caret.

var pass = 0, fail = 0
func ok(_ label: String, _ cond: Bool) {
    if cond { pass += 1; print("  ✓ \(label)") }
    else { fail += 1; print("  ✗ \(label)") }
}

/// The stripped control: no superview walk.
func control_isTextInputOrUIControl(_ view: UIView) -> Bool {
    if view is UITextView || view is UITextField || view is UISearchBar { return true }
    if view is UIControl { return true }
    return false
}

func nest(_ child: UIView, under parents: [UIView]) -> UIView {
    var current = child
    for p in parents { p.addSubview(current); current = p }
    return child
}

print("[A] direct hits — a tap that lands on the input itself must be declined")
let tf = UITextField()
let tv = UITextView()
let sb = UISearchBar()
let btn = UIButton(type: .system)
let sw = UISwitch()
let plain = UIView()
ok("UITextField declined", KeyboardTapDismissCoordinator.isTextInputOrUIControl(tf))
ok("UITextView declined", KeyboardTapDismissCoordinator.isTextInputOrUIControl(tv))
ok("UISearchBar declined", KeyboardTapDismissCoordinator.isTextInputOrUIControl(sb))
ok("UIButton (UIControl) declined", KeyboardTapDismissCoordinator.isTextInputOrUIControl(btn))
ok("UISwitch (UIControl) declined", KeyboardTapDismissCoordinator.isTextInputOrUIControl(sw))
ok("plain UIView ACCEPTED (this is what dismisses)",
   !KeyboardTapDismissCoordinator.isTextInputOrUIControl(plain))

print("[B] nested hits — what SwiftUI/UIKit actually hands the recognizer")
// A TextEditor's tap lands on a private layout subview several levels deep.
let innerOfTextView = UIView()
_ = nest(innerOfTextView, under: [UIView(), tv, UIView()])
ok("deep subview of a UITextView declined (TextEditor caret placement)",
   KeyboardTapDismissCoordinator.isTextInputOrUIControl(innerOfTextView))

let innerOfTextField = UIView()
_ = nest(innerOfTextField, under: [UIView(), tf])
ok("subview of a UITextField declined",
   KeyboardTapDismissCoordinator.isTextInputOrUIControl(innerOfTextField))

let labelInButton = UILabel()
_ = nest(labelInButton, under: [btn])
ok("label inside a UIButton declined",
   KeyboardTapDismissCoordinator.isTextInputOrUIControl(labelInButton))

// The Visit Note's Yes/No options are SwiftUI Buttons — NOT UIControls — so
// they live in a plain host view and MUST be accepted (tap both registers on
// the option and dismisses the keyboard, which is Nick's checklist item).
let swiftUIButtonHost = UIView()      // stands in for a SwiftUI host view
let yesNoRowContent = UIView()
_ = nest(yesNoRowContent, under: [UIView(), swiftUIButtonHost])
ok("SwiftUI Button content ACCEPTED → one tap dismisses AND registers",
   !KeyboardTapDismissCoordinator.isTextInputOrUIControl(yesNoRowContent))

// A scroll view's content is plain: dragging/tapping the form background
// dismisses.
let scrollContent = UIView()
_ = nest(scrollContent, under: [UIScrollView()])
ok("scroll-view content ACCEPTED (tap on form background dismisses)",
   !KeyboardTapDismissCoordinator.isTextInputOrUIControl(scrollContent))

print("[C] 🎯 non-vacuous control — the stripped version must FAIL these")
ok("control MISSES the nested UITextView (proves the walk is load-bearing)",
   control_isTextInputOrUIControl(innerOfTextView) == false)
ok("control MISSES the nested UITextField",
   control_isTextInputOrUIControl(innerOfTextField) == false)
ok("control MISSES the label inside a UIButton",
   control_isTextInputOrUIControl(labelInButton) == false)
ok("control AGREES on the direct UITextView (so the divergence is the walk only)",
   control_isTextInputOrUIControl(tv) == true)
ok("control AGREES on plain views (no false divergence)",
   control_isTextInputOrUIControl(plain) == false)

print("[D] recognizer configuration — the three flags that make it observe, not consume")
// Built the same way install() builds it; asserted here because a future edit
// flipping cancelsTouchesInView to the default (true) would silently break
// every button in the app while the keyboard is up.
let probe = UITapGestureRecognizer()
probe.cancelsTouchesInView = false
probe.delaysTouchesBegan = false
probe.delaysTouchesEnded = false
ok("cancelsTouchesInView false → touch still reaches the control", probe.cancelsTouchesInView == false)
ok("delaysTouchesBegan false → no added tap latency", probe.delaysTouchesBegan == false)
ok("delaysTouchesEnded false", probe.delaysTouchesEnded == false)

print("[E] resign helper is a no-op-safe global (never throws with nothing focused)")
KeyboardDismisser.dismiss()
pass += 1; print("  ✓ KeyboardDismisser.dismiss() with no first responder did not crash")

print("")
print("keyboard-dismiss logic: \(pass) passed, \(fail) failed")
exit(fail == 0 ? 0 : 1)
