# Incomplete SPSC sleep trial during clock-benchmark verification

The clock-benchmark validation observed one incomplete trial on the development
host, with a ReleaseFast binary compiled before the runtime's final
`threadAdmissionEnded` wakeup fix. `subprocess.run(timeout=45)` raised
`TimeoutExpired` and terminated that trial. No result row was produced, so no
accepted count, written throughput, or passing result is attributed to it.

Exact command:

```text
/tmp/kron-bench-clock --events=127 --samples=31 --warmup-events=17 \
  --work-dir=/tmp/kron-bench-validation-d7glt8n6 \
  --mode=spsc --producers=16 --idle=sleep
```

The same scenario had completed in earlier runs, and one subsequent isolated
reproduction completed. That does not erase the observed timeout. Runtime work
identified a final producer-admission completion without a sleeping-worker
wakeup; the runtime fix and final rebuilt validation are tracked separately.
This record concerns shutdown/liveness, not clock-dispatch timing advantage.

At capture, other bounded clock scenarios passed: dynamic/std.Io/native/none
producer paths, actual SPSC static-clock attachment, zero timestamps in file
output, and clock-only checksum/count validation. No process remained alive
after the timeout/reproduction checks.

## Single rebuilt validation after the wakeup fix

The parent applied the admission-completion wakeup fix and passed a deterministic
held-admission regression. A single freshly compiled ReleaseFast executable was
then validated without retrying the suite:

```text
python3 -u bench/validate.py --binary /tmp/kron-bench-clock-fast-final \
  --timeout-seconds=45
```

The first ten scenarios completed: sync zero fields, sync short/cold, sync long,
text, logfmt, filtered, shared async, async overload, SPSC, and SPSC long. The
next SPSC sleep invocation timed out during initialization with no result row:

```text
/tmp/kron-bench-clock-fast-final --events=127 --samples=31 \
  --warmup-events=17 --work-dir=/tmp/kron-bench-validation-n69fg010 \
  --mode=spsc --producers=16 --idle=sleep
```

A bounded live inspection before timeout found PID 3762562 with **only its main
thread**; `/proc/3762562/task/3762562/wchan` reported `folio_wait_bit_common`.
No collector or producer threads existed yet. This is evidence of a wait during
file/page initialization, rather than the earlier sleeping-worker shutdown
condition. The host concurrently ran repository verification, so storage pressure
is a possible cause; it is not established as the sole cause by this observation.
Python's timeout terminated the trial, the suite stopped, and no loop/retry was
started. Remaining scenarios were not executed by this rebuilt full-suite run.
The binary hash and complete command are preserved in
`final-validation-timeout.json`.
