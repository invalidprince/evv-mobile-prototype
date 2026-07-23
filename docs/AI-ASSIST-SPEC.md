# AI Assist — Documentation Drafting Feature Spec

**Status:** Draft for Nick's review
**Date:** 2026-07-23
**Feature flag:** `ai_assist_enabled` (org-level, default off until BAA confirmed)

## Summary

Staff describe the visit in their own words (typed or dictated via native keyboard mic). AI maps their description into the structured documentation form (Outcomes & Goals, Health & Safety, Additional Comments) as a **draft**. Staff review, edit, and submit. Anything the staff member did not mention is left blank and flagged — the AI never invents content.

## Guiding Principles (non-negotiable)

1. **AI structures, never authors.** Output must only contain information present in the staff member's input. No embellishment, no inferred clinical language, no filler.
2. **Staff own the note.** Mandatory review step; submit is blocked until staff has scrolled/visited each populated section. Edits are expected and encouraged.
3. **Gaps are flagged, not filled.** If staff didn't mention an active outcome/goal, that field renders empty with a red "Not mentioned — please complete" chip.
4. **Auditability.** Notes store `ai_assisted: true`, the original staff input text, model id, and timestamp. Full trail if licensing/audit ever asks.
5. **PHI safety.** Requests only go to an AI provider under a signed BAA. Feature is hard-disabled otherwise.

## UX Flow

1. In DocumentationView, new button: **"✨ AI Assist"** (only visible when online + feature flag on).
2. Sheet opens: "Describe the visit in your own words." Large text area + hint text with an example. Staff can use native dictation.
3. Staff taps **Generate Draft** → loading state (target < 8s).
4. Draft lands in the structured form:
   - Populated fields get a subtle "AI draft" badge until edited or confirmed.
   - Unmentioned outcomes/health fields get red "Not mentioned" chips.
5. Staff edits/completes, then submits normally. Submit payload includes `ai_assisted`, `ai_input_text`, `ai_model`.
6. Dashboard visit detail shows a small "AI-assisted" indicator for managers/QA.

## Backend

### New endpoint
`POST /api/visits/:id/ai-draft`
- Body: `{ inputText }`
- Server loads the individual's documentation template (existing endpoint from v1.1.335): active outcomes/goals, health tracking fields.
- Server calls the AI provider with a strict system prompt (below), the template, and the staff input.
- Response: same shape as the structured note payload, plus `unaddressed: [fieldIds]`.
- Rate limit: e.g. 10/staff/hour. Log usage per org.

### Prompt design (server-side, never client-side)
System prompt requirements:
- Role: documentation formatter for an IDD services provider.
- ONLY use facts stated in the staff input. If a field is not addressed, return null for it.
- Preserve staff voice in narratives; correct grammar lightly; no clinical jargon the staff didn't use.
- Map prompt-level / frequency language ("needed two verbal prompts") onto the outcome entry fields when the template defines them.
- Output: strict JSON matching the documentation payload schema (use tool/structured output mode, not freeform).

### Storage (idempotent migration)
- `visit_notes` (or equivalent) gains: `ai_assisted BOOLEAN DEFAULT FALSE`, `ai_input_text TEXT`, `ai_model TEXT`.

### Provider
- Anthropic API (Claude) under BAA, or org's preferred BAA-covered provider.
- API key server-side only. Timeout 20s, graceful failure ("AI Assist unavailable — write your note normally").

## iOS

- `AIAssistSheet.swift`: input sheet + generate button + error states.
- DocumentationView: accept a prefilled draft payload; render "AI draft" badges + "Not mentioned" chips; track per-section visited state to gate submit.
- Offline: button hidden (assist requires connectivity); normal manual documentation unaffected.
- No streaming needed v1 — single response is fine.

## Compliance Checklist (before enabling for real PHI)

- [ ] BAA signed with AI provider
- [ ] Confirm policy language: staff remain responsible for note accuracy (add to training/policy doc)
- [ ] QA review sample of AI-assisted notes in first 30 days (Getty/Amy loop-in)
- [ ] Retention: ai_input_text covered by same retention policy as notes

## Rollout Plan

1. **Phase 1 (build):** Backend endpoint + iOS sheet behind feature flag. Test with demo data only. (~1 session)
2. **Phase 2 (pilot):** Enable for Nick + 2-3 trusted staff on real visits post-BAA. Compare note quality vs manual. (~1 session for fixes)
3. **Phase 3 (org rollout):** Enable org-wide, add manager-side AI-assisted indicator reporting.

## Open Questions for Nick

1. Which provider do you want under BAA — Anthropic direct, or route through something you already have covered?
2. Should managers see the original staff input text on the dashboard, or just the final note?
3. Voice: happy with native keyboard dictation, or eventually want in-app audio recording → transcription (Whisper)? (v2 material)
4. Any state/PA-specific documentation rules that constrain AI involvement in service notes? (Worth a quick check with Amy/compliance before pilot.)
