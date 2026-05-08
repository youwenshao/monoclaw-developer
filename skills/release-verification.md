# Release Verification Skill

Use this before publishing installer, runtime, or website changes.

## Checklist

- Confirm every changed repo has a clean or intentionally documented git state.
- Run the smallest command that proves each changed surface still works.
- Run the runtime identity audit and classify any remaining upstream references.
- Run Hatch preflight in dry-run mode before any real installer test.
- Check that no secrets, model weights, vendor bundles, or provisioning logs are
  staged.
- For website changes, run unit tests and build unless blocked by missing
  environment values; document any blocked checks.
