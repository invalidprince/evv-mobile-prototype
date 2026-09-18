import SwiftUI
import UIKit

// MARK: - Keyboard dismissal (build 75, Todoist 6hWwwmxrqchxrf7H)
//
// Nick, #evv 2026-09-17: "Spec this too for iOS to have a way to bring down
// the keyboard (hide it)" — filed against the Visit Note form, where stacked
// required questions meant the keyboard covered the lower fields (the police
// involvement free-text) and there was NO way to put it away: no Done bar, no
// drag-to-dismiss, no tap-outside. Nothing in the app had any of the three.
//
// Three stock-iOS affordances, all driven from ONE modifier applied at each
// screen's root — `.keyboardDismissable()`:
//
//   1. Done bar     — ToolbarItemGroup(placement: .keyboard)
//   2. Drag down    — .scrollDismissesKeyboard(.interactively) (iOS 16+)
//                     + a UIKit .interactive fallback for the iOS 15 target
//   3. Tap outside  — a window-level UITapGestureRecognizer
//
// 🔑 WHY RESIGN VIA UIKit AND NOT @FocusState
// -------------------------------------------
// 16 input surfaces across 15 files, and exactly ONE of them had a
// @FocusState (OutcomeEntryView's CountRow). Threading a shared focus enum
// through every sheet would mean touching every field binding on a task whose
// whole point is "no behavior change to what's submitted". `sendAction(
// resignFirstResponder)` asks UIKit to drop whatever is first responder, so it
// works for TextField, SecureField AND TextEditor without the call site
// knowing which field is up — and it cannot desynchronise a focus binding it
// never owned. The one existing @FocusState keeps working: CountRow commits
// its typed value in `.onChange(of: focused)`, which fires on resign exactly
// as it does when the user taps elsewhere today.
//
// 🩸 WHY THE TAP-OUTSIDE IS A UIKit RECOGNIZER AND *NOT* .onTapGesture
// --------------------------------------------------------------------
// The obvious SwiftUI spelling — `.onTapGesture { dismiss }` on the screen's
// container, or `.simultaneousGesture(TapGesture())` — BREAKS the very screen
// this card is about. The Visit Note's Yes/No rows are `Button`s
// (VisitQuestionCard.radioButton, .buttonStyle(.plain)); a container tap
// gesture competes with them, so while the keyboard is up a Yes/No tap either
// does nothing or needs a second tap. Nick's checklist explicitly requires
// "tap on a Yes/No segment while keyboard is up both dismisses AND registers".
//
// A UITapGestureRecognizer on the UIWindow with
//
//      cancelsTouchesInView = false   →  the touch still reaches the view it
//                                        hit, so the Button/segment/row fires
//      delaysTouchesBegan   = false   →  no added latency on every tap
//      delaysTouchesEnded   = false
//
// observes taps instead of consuming them: one tap both registers on the
// control and drops the keyboard. `shouldRecognizeSimultaneouslyWith` returns
// true so it never fights SwiftUI's own recognizers (scroll, long-press,
// the signature pad's drag).
//
// It also declines the taps that must NOT dismiss:
//   • taps inside a UITextView/UITextField (moving the caret, selecting text,
//     or tapping the field you are already editing) — dismissing there makes
//     the field unusable;
//   • taps on a UIKit control (UIButton/UISwitch/UISlider…) that the system
//     routes through a control action, where a simultaneous resign can eat the
//     hit — SwiftUI Buttons are not UIControls, so those still dismiss, which
//     is what Nick asked for;
//   • taps while no keyboard is up (tracked off the keyboard notifications),
//     so the recognizer is inert on every screen with no text input.

// MARK: - Resign helper

enum KeyboardDismisser {
    /// Drop whatever is first responder. Safe to call when nothing is focused.
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }
}

// MARK: - Window-level tap-to-dismiss

/// Installs (once per window) a non-consuming tap recognizer that dismisses
/// the keyboard. Idempotent: every screen applying `.keyboardDismissable()`
/// calls install, and only the first one for a given window attaches.
final class KeyboardTapDismissCoordinator: NSObject, UIGestureRecognizerDelegate {

    static let shared = KeyboardTapDismissCoordinator()

    /// Windows we've already attached to. Weak so a torn-down window doesn't
    /// leak and a fresh one gets its own recognizer.
    private let attached = NSHashTable<UIWindow>.weakObjects()

    /// Only dismiss when a keyboard is actually on screen — otherwise the
    /// recognizer fires resignFirstResponder on every tap in the whole app.
    private var keyboardVisible = false

    private override init() {
        super.init()
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(keyboardShown),
                       name: UIResponder.keyboardDidShowNotification, object: nil)
        nc.addObserver(self, selector: #selector(keyboardHidden),
                       name: UIResponder.keyboardDidHideNotification, object: nil)
    }

    @objc private func keyboardShown() { keyboardVisible = true }
    @objc private func keyboardHidden() { keyboardVisible = false }

    func install() {
        // Must run on the main thread and after the window exists; the modifier
        // calls this from .onAppear, which satisfies both.
        guard let window = Self.activeWindow(), !attached.contains(window) else { return }
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        // The three lines that make this observe rather than consume.
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delaysTouchesEnded = false
        tap.requiresExclusiveTouchType = false
        tap.delegate = self
        window.addGestureRecognizer(tap)
        attached.add(window)
    }

    @objc private func handleTap() {
        guard keyboardVisible else { return }
        KeyboardDismisser.dismiss()
    }

    // MARK: UIGestureRecognizerDelegate

    /// Never fight SwiftUI's recognizers — scrolling, long-press, the
    /// signature pad's drag all keep working.
    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        guard keyboardVisible else { return false }
        guard let hit = touch.view else { return true }
        return !Self.isTextInputOrUIControl(hit)
    }

    /// Walk up from the hit view: a tap that lands in a text input (caret
    /// placement / selection) or on a UIKit control must not be shadowed.
    static func isTextInputOrUIControl(_ view: UIView) -> Bool {
        var node: UIView? = view
        while let v = node {
            if v is UITextView || v is UITextField || v is UISearchBar { return true }
            if v is UIControl { return true }
            node = v.superview
        }
        return false
    }

    static func activeWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        // Prefer the foreground-active scene's key window.
        if let w = scenes.first(where: { $0.activationState == .foregroundActive })?
            .windows.first(where: { $0.isKeyWindow }) {
            return w
        }
        return scenes.flatMap(\.windows).first(where: { $0.isKeyWindow })
            ?? scenes.flatMap(\.windows).first
    }
}

// MARK: - The modifier

/// Applies all three dismissal affordances. Put it on a screen's ROOT view
/// (the NavigationView/Form/ScrollView container), not on individual fields.
struct KeyboardDismissable: ViewModifier {

    /// Some screens (the signature pad) own their own drag gestures; they can
    /// opt out of interactive scroll dismissal while keeping Done + tap.
    var interactiveDrag: Bool = true

    func body(content: Content) -> some View {
        applyDrag(to: content)
            .toolbar {
                // The Done bar. `placement: .keyboard` renders ONLY while a
                // keyboard is up, so this adds no chrome to any screen and
                // costs nothing on screens with no text input.
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { KeyboardDismisser.dismiss() }
                        .font(.body.weight(.semibold))
                        .accessibilityLabel("Hide keyboard")
                        .accessibilityIdentifier("keyboard-done")
                }
            }
            .onAppear { KeyboardTapDismissCoordinator.shared.install() }
    }

    @ViewBuilder
    private func applyDrag(to content: Content) -> some View {
        if #available(iOS 16.0, *), interactiveDrag {
            // Drag the scroll content down and the keyboard follows the finger.
            content.scrollDismissesKeyboard(.interactively)
        } else {
            // Deployment target is 15.0 (IPHONEOS_DEPLOYMENT_TARGET = 15.0), so
            // the modifier above cannot be unconditional. On 15 the UIKit
            // appearance proxy gives drag-to-dismiss on scroll views created
            // after it is set; harmless on 16+ where the modifier wins.
            content.onAppear {
                UIScrollView.appearance().keyboardDismissMode = .interactive
            }
        }
    }
}

extension View {
    /// Done bar + drag-to-dismiss + tap-outside-to-dismiss for every text
    /// input on this screen. Apply at the screen root.
    func keyboardDismissable(interactiveDrag: Bool = true) -> some View {
        modifier(KeyboardDismissable(interactiveDrag: interactiveDrag))
    }
}
