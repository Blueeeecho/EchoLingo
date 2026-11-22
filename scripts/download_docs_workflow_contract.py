"""Remove only the approved download-docs wiring for legacy CI comparisons."""
import re


def without_download_docs(workflow):
    """Keep the full-mode executable job and all historical routing byte exact."""
    if "mode=download-docs" not in workflow:
        return workflow
    header = """          CI_BEFORE: ${{ github.event.pull_request.base.sha || github.event.before }}
          CI_HEAD: ${{ github.event.pull_request.head.sha || github.sha }}
"""
    selector = """          # Require a complete, append-only Git history and the exact safe path/file-mode set.
          if { { [ "$CI_EVENT" = pull_request ] && [ "$PR_BASE" = main ]; } || { [ "$CI_EVENT" = push ] && [ "$CI_REF" = refs/heads/main ]; }; } &&
             [[ ${CI_BEFORE:-} =~ ^[0-9a-f]{40}$ && ${CI_HEAD:-} =~ ^[0-9a-f]{40}$ ]] &&
             (set -o pipefail; git show "$CI_BEFORE:scripts/check-download-docs.py" 2>/dev/null |
                python3 -I - --scope "$CI_BEFORE" "$CI_HEAD"); then
            echo "mode=download-docs" >> "$GITHUB_OUTPUT"
            exit 0
          fi
"""
    route = "needs.validation-mode.outputs.mode != 'download-docs'"
    light_job = """      - name: Verify download documentation against its published release
        if: needs.validation-mode.outputs.mode == 'download-docs'
        env:
          GH_TOKEN: ${{ github.token }}
          DOCS_BEFORE: ${{ github.event.pull_request.base.sha || github.event.before }}
          DOCS_HEAD: ${{ github.sha }}
        run: |
          python3 scripts/check-download-docs.py --scope "$DOCS_BEFORE" "$DOCS_HEAD"
          python3 scripts/check-repository.py
          python3 scripts/check-download-docs.py --published
"""
    for exact in (header, selector, light_job):
        assert workflow.count(exact) == 1, "Unexpected download documentation workflow wiring"
        workflow = workflow.replace(exact, "", 1)

    def original_gate(match):
        body = match[1]
        if body.startswith("(") and body.endswith(")"):
            return "    if: " + body[1:-1]
        return "    if: " + body

    workflow, gates = re.subn(r"^    if: " + re.escape(route) + r" && (.*)$",
                              original_gate, workflow, flags=re.MULTILINE)
    assert gates == 6, "Unexpected change in native job routing"
    before, frontend = workflow.split("  frontend-interactions:\n", 1)
    frontend, after = frontend.split("\n  windows-popup-diagnostics:", 1)
    deps = f"      - if: {route}\n        run: npm ci\n"
    gated = f"        if: {route}\n"
    docs_check = "          python3 scripts/check-download-docs.py\n"
    artifact = f"        if: always() && {route}\n"
    assert frontend.count(deps) == frontend.count(docs_check) == frontend.count(artifact) == 1
    assert frontend.count(gated) == 7
    frontend = frontend.replace(deps, "      - run: npm ci\n", 1)
    frontend = frontend.replace(gated, "").replace(docs_check, "", 1)
    frontend = frontend.replace(artifact, "        if: always()\n", 1)
    return before + "  frontend-interactions:\n" + frontend + "\n  windows-popup-diagnostics:" + after
