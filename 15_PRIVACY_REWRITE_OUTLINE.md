# 15 — PRIVACY POLICY REWRITE + ToS OUTLINE

**Status:** DRAFT outline — prepared by the EXECUTOR seat, 2026-06-22. **Not legal advice.** This is the structure + gap analysis we hand to counsel (`14`) for redline; the redlined text then lands in each app repo and is hosted at a public URL.

---

## 1. Current-state gap analysis

| Doc | Verdict | Key problems |
|---|---|---|
| BSPC `ACTIVE/docs/privacy-policy.md` | **needs-work** (best of the set) | Genuinely covers children's privacy, third parties, 30-day deletion SLA. But "we do not collect photos or videos" (`:72`) is true only for BSPC in isolation — the same operator's Coach app does, on the same kids. Placeholder contact `privacy@bspowercats.com` (`:154`). No public URL. No verifiable-consent *mechanism* described. |
| Coach `PRIVACY_POLICY.md` | **placeholder-draft / not launch-ready** | Children's-privacy section is one thin paragraph leaning on "not directly collected from children" (`:66-68`); **does not disclose** collection of minors' video/audio/medical. Names **Firebase + Vertex** as processors (backend is moving to Supabase) — stale. No deletion SLA; deletion is "email the admin." No SafeSport/photo-consent language despite the app having a `mediaConsent` gate. |
| Coach `TERMS_OF_SERVICE.md` | **needs-work** | Reasonable structure, MO law, AI disclaimer. Never addresses that the data subjects are **minors** or that parental authority is required to enter a child. Names Vertex (stale). |
| BSPC ToS | **absent** | No Terms of Service exists anywhere in BSPC. |
| Coach `SECURITY.md` | launch-ready | Strong threat model (COPPA/SafeSport bypass, invite flaws, secret exposure). No change needed. |

## 2. `[DECIDE]` — one policy or two?

**Executor recommendation:** a single **operator-level privacy policy** covering all three surfaces (same operator, same families, same children) — it eliminates the cross-app contradiction by construction. Alternative: two app-specific policies that explicitly cross-reference. Counsel + Kevin to decide.

## 3. Target privacy-policy outline (section by section)

1. **Operator identity & contact** — who operates the apps; a real monitored contact email *(replace placeholder)*.
2. **Scope** — names all three surfaces (parent app, coach app, parent-portal) and that they share one backend.
3. **Who uses the apps** — adults only (coaches 18+, parents/guardians); children have no accounts.
4. **Data we collect** — split into (a) adult account data and (b) **data about minors** — and be explicit about the minor-media/medical categories (`14 §3`). No more "we don't collect photos/videos" at the operator level.
5. **How it's collected & the consent step** — entered by coaches/parents; describe the *actual* parental-consent mechanism (whatever counsel lands on in `14 §7.2`) — the policy must match the mechanism.
6. **How we use it** — team operations, performance tracking, AI coaching analysis; explicitly **no advertising, no sale of data**.
7. **Legal basis / parental consent** — the COPPA/parental-consent posture counsel recommends.
8. **Third-party processors** — accurate list: **Supabase** (DB/auth/storage), **Sentry** (crash), **PostHog** (analytics), **Google Cloud / Vertex AI – Gemini** (Coach AI media analysis), **Expo** (push/builds). Remove Firebase once the cutover completes; until then, disclose it as transitional.
9. **Storage & security** — US region; Row-Level Security; secure token storage; consent enforced at the data layer *(after the Gate-1 fix)*.
10. **Retention & deletion** — concrete retention defaults + a deletion SLA (BSPC's 30-day model is a good baseline); include **media**.
11. **Parental rights** — review, correct, and delete the child's specific data; how to exercise; response SLA.
12. **Children's privacy / COPPA / SafeSport** — the real, matching treatment (replaces both the BSPC and Coach versions).
13. **Data-safety summary** — mirrors what we'll attest on the store forms.
14. **Effective date & changes** — real date *(replace placeholder)*; change-notification process.

## 4. BSPC Terms of Service — skeleton (currently missing)

1. Acceptance of terms. 2. **Eligibility** — 18+ to hold an account; account holder affirms parental/guardian authority to enter a swimmer. 3. Description of service. 4. Acceptable use. 5. User-provided content & accuracy. 6. **Disclaimers** — informational only; not medical advice; AI outputs are coach-reviewed. 7. Limitation of liability. 8. Termination. 9. **Governing law — Missouri** (match the Coach ToS). 10. Changes to terms. 11. Contact. *(Coach already has a ToS — align the two; add the minors/parental-authority clause to it as well.)*

## 5. Cross-app consistency checklist (contradictions to eliminate)

- [ ] No surface-specific "we don't collect X" claim that's false at the operator level.
- [ ] Processor lists identical and accurate across all docs (Supabase-first; Firebase only as transitional; include Vertex/Gemini + Sentry + PostHog).
- [ ] Every consent claim in copy (incl. the in-app `edit.tsx:351-353` label) matches the implemented mechanism.
- [ ] Deletion SLA + parental-rights language present and identical across surfaces.
- [ ] Effective dates and contact emails real and consistent.

## 6. Placeholders to replace before publish

- Contact email `privacy@bspowercats.com` / `support@bspowercats.com` → a real monitored inbox.
- Privacy Policy URL + Support URL (currently `[To be created]` in BSPC `app-store-metadata.md`) → hosted public URLs *(both stores hard-require a reachable privacy URL).*
- Effective dates → real dates at publish.

## 7. Where the redlined text lands (after counsel)

- BSPC: `BSPC/ACTIVE/docs/privacy-policy.md` (+ new `terms-of-service.md`), hosted at a public URL, URL filled into `app-store-metadata.md`.
- Coach: `BSPC-Coach-App/PRIVACY_POLICY.md` + `TERMS_OF_SERVICE.md`, hosted, URLs into store metadata.
- In-app: update the `edit.tsx` media-consent copy to match the final mechanism.
- These are app-repo edits — **out of scope until counsel returns and the director rules**; tracked here only as the destination.
