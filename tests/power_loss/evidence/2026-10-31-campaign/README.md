# Bounded child-VM crash campaign

Four independent scratch VMs were terminated abruptly after durability
acknowledgements17,31,8 and3. All verifier boots recovered every acknowledged
file record and a journal checkpoint at or above the acknowledged sequence.
The journal has16 slots, so17 and31 exercise slot reuse rather than only the
first mapping contents.

[results.json](results.json) records executable/kernel/busybox hashes, commands,
elapsed time, raw image hashes and original evidence locations. Compact logs
are preserved here; large raw images remain outside the package. Verification
uses a temporary snapshot overlay and confirms the crash base image unchanged.

This is a bounded, seeded campaign on one Linux/ext4 configuration. It is not a
physical host power cut, a long randomized stress qualification, or evidence
that unacknowledged data must disappear. Only acknowledged durability is asserted.
