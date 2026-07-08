# Admin Console screenshots

Lab 4 (Org Governance Walkthrough) is screenshot-led. Capture the screenshots below from a real Docker Business org with AI Governance Early Access enabled, then drop them into this directory with the listed filenames.

## Required screenshots

| Filename | What to capture |
|----------|-----------------|
| `01-admin-console-nav.png` | Left navigation in `app.docker.com/admin` showing the "AI governance settings" entry. Annotate the section with a callout arrow. |
| `02-network-access-rules.png` | The Network access page with 5–8 allow/deny rules visible (mix of exact domains, wildcards, CIDRs). Show the action column (allow / deny). |
| `03-filesystem-access-rules.png` | The Filesystem access page with paths showing both `**` recursive patterns and read-only/read-write modes. |
| `04-delegation-user-defined.png` | The "User defined" toggle UI for at least one rule type, with the on/off state visible. Best if you can show one type delegated and another not. |
| `05-mcp-catalog-admin.png` | The MCP catalog admin page - list of approved servers, with at least one row showing per-tool allow/deny within a server. |

## Capture tips

- Use 2× / Retina display capture if possible - the lab renders these at full width.
- Annotate with red callouts where the key element is (Mac: Preview's annotation tools; Windows: Snip & Sketch).
- Crop tightly. The labspace UI scales images down; tighter crops keep text readable.
- Avoid capturing real org names, real domains your customer hasn't pre-approved for marketing, or any internal-only test data. Use `bosch-example.com`, `acme.example`, etc. as placeholders.

## If you don't have an enabled org yet

If you need to run the workshop before you can get AI Governance Early Access provisioned, two alternatives:

1. **Use mock screenshots.** Build wireframes in Figma / Excalidraw that show the same fields and rule shapes from the public docs. Label them clearly as illustrative.
2. **Use docs page screenshots.** The public docs page (<https://docs.docker.com/ai/sandboxes/security/governance/>) doesn't currently include UI screenshots, so this option is limited - but if anything gets added there, you can use it directly.

Either way, the **CLI side** (`sbx policy ls` output showing `ORIGIN: remote` rules) is reproducible without any Admin Console access - that's the more important piece anyway, since it's what the developers actually see day-to-day.
