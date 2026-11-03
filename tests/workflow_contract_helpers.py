"""Compare executable job contracts separately from conservative CI routing.

No YAML dependency: only top-level job routing fields may differ; nested step
conditions, failure policy, commands and artifact preservation stay byte-exact.
"""
import re


_ROUTE = r"needs\.validation-mode\.outputs\.mode != '(?:language-routing-patch-v1|screenshot-pins|macos-followup|automatic-direction|routing-release|windows-unpack)'"


def executable_job(job):
    # strip() on callers may remove the first field's indentation only.
    lines = job.strip().splitlines()
    if lines:
        lines[0] = '    ' + lines[0].lstrip()
    executable = []
    for line in lines:
        if line == '    needs: validation-mode':
            continue
        if line.startswith('    if: '):
            condition = line.removeprefix('    if: ')
            if not re.fullmatch(rf'{_ROUTE}(?: && {_ROUTE})*', condition):
                raise AssertionError(f'Unexpected job routing condition: {condition}')
            continue
        executable.append(line)
    return '\n'.join(executable).strip()


def assert_pull_request_gate(test, job):
    gates = re.findall(r'^    if: (.+)$', job, flags=re.MULTILINE)
    test.assertEqual(len(gates), 1)
    # A scope exclusion may narrow PR execution, never broaden it to pushes,
    # manual runs or write-capable events. OR/always()/false are not accepted.
    test.assertRegex(gates[0], rf"^(?:{_ROUTE} && )*github\.event_name == 'pull_request'$")
