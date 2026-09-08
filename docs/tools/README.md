# Device test plan generator

`gen_plan.py` holds the 162 scenarios, the per-row results (`RESULTS`) and the run log (`RUNS`)
and writes `../DEVICE_TEST_PLAN.md` plus an HTML page (`releva-sdk-device-test-plan.html`, from
`plan_template.html`) that is published as a checkable artifact.

    python3 docs/tools/gen_plan.py

Edit `RESULTS` / `RUNS` in the script, regenerate, commit the Markdown together with the script.
