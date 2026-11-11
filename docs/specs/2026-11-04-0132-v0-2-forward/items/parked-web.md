# Parked — Web compilation (JS/HTML/CSS)

**Status: trigger fired — milestone W** (spec
`docs/specs/2026-11-10-web-target/`; the guardrail held — the GUI
backend protocol ported to DOM with no toolkit-shaped
assumptions). This note is historical.

The design doc parks the web target explicitly. The only required
guardrail for this milestone:

When F1 (GUI pilot) lands, keep its notes about what a portable widget
layer would need — the same widget tree that would render to a GPU
surface renders to DOM later. Any design choice in F1 that would make
that mapping *impossible* is a red flag worth surfacing, not blocking.

Re-open this item only after the GUI story exists (path b in the
design doc's own ordering).
