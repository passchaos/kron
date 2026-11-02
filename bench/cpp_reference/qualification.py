"""Paired local qualification for the two requested Foundation frontends.

Ratios above one always favor kron. Resampling pairs preserves round identity;
neither a positive median nor a narrow ratio interval overrides noisy inputs.
This qualifies this workload and host window, not a universal library ranking.
"""
import math
import random
import statistics

PEERS = ("foundation", "foundation_tracing")
NOISE_LIMIT = .10
BOOTSTRAP_DRAWS = 10000


def _spread(values):
    median = statistics.median(values)
    return (max(values) - min(values)) / median if median else math.inf


def paired_metric(kron, peer, metric, higher_is_better=True):
    def rounds(rows):
        result = {row["repetition"]: row for row in rows}
        if len(result) != len(rows):
            raise ValueError("duplicate repetition in paired comparison")
        return result

    first, second = rounds(kron), rounds(peer)
    if not first or first.keys() != second.keys():
        raise ValueError("paired comparison requires identical nonempty rounds")
    ids = sorted(first)
    a, b = [first[i][metric] for i in ids], [second[i][metric] for i in ids]
    if any(not math.isfinite(value) or value <= 0 for value in a + b):
        return {"assessment": "inconclusive", "reason": "nonpositive_or_nonfinite_measurement", "rounds": ids}
    ratios = [x / y if higher_is_better else y / x for x, y in zip(a, b)]
    rng = random.Random(0x6b726f6e)
    draws = sorted(statistics.median(rng.choices(ratios, k=len(ratios))) for _ in range(BOOTSTRAP_DRAWS))
    interval = [draws[249], draws[9749]]
    spreads = {"kron": _spread(a), "peer": _spread(b), "paired_ratio": _spread(ratios)}
    stable = len(ids) >= 5 and all(value <= NOISE_LIMIT for value in spreads.values())
    assessment = "inconclusive"
    if stable and interval[0] > 1:
        assessment = "kron_leads"
    elif stable and interval[1] < 1:
        assessment = "peer_leads"
    return {"assessment": assessment, "rounds": ids, "kron_median": statistics.median(a),
            "peer_median": statistics.median(b), "paired_speed_ratio": statistics.median(ratios),
            "paired_ratios": ratios, "paired_ratio_ci95": interval, "relative_spread": spreads,
            "repeatability_qualified": stable, "higher_is_better": higher_is_better}


def foundation_comparisons(grouped):
    comparisons = []
    missing = []
    for (library, configuration, producers, phase), selected in sorted(grouped.items()):
        if library != "kron":
            continue
        parts = configuration.split("-")
        if len(parts) != 3 or parts[0] not in ("async", "spsc") or parts[1] not in ("memory", "mmap"):
            raise ValueError("unknown kron comparison configuration")
        storage = parts[1]
        for peer in PEERS:
            other = grouped.get((peer, storage, producers, phase))
            if other is None:
                missing.append({"kron_configuration": configuration, "peer": peer, "producers": producers, "phase": phase})
                continue
            for row in selected + other:
                if row["metadata"] != "full" or row["storage"] != storage:
                    raise ValueError("Foundation qualification requires the common full JSON workload")
            metrics = {metric: paired_metric(selected, other, metric) for metric in
                       ("written_records_per_sec", "written_flush_records_per_sec", "lifecycle_records_per_sec")}
            for metric in ("init_ns", "shutdown_ns") + (("p50_ns", "p99_ns", "p999_ns") if phase == "sampled" else ()):
                metrics[metric] = paired_metric(selected, other, metric, higher_is_better=False)
            comparisons.append({"kron_configuration": configuration, "peer": peer, "storage": storage,
                                "producers": producers, "phase": phase, "metrics": metrics})
    throughput = [item["metrics"]["written_records_per_sec"]["assessment"] for item in comparisons]
    peers = {item["peer"] for item in comparisons}
    outcome = "inconclusive"
    if not missing and peers == set(PEERS) and throughput and all(item == "kron_leads" for item in throughput):
        outcome = "kron_leads_both_frontends_in_selected_cases"
    elif any(item == "peer_leads" for item in throughput):
        outcome = "target_not_met_in_selected_cases"
    return {"written_close_assessment": outcome, "comparisons": comparisons, "missing_pairs": missing,
            "noise_limit": NOISE_LIMIT, "minimum_rounds": 5, "bootstrap_draws": BOOTSTRAP_DRAWS,
            "ratio_direction": "above one favors kron for throughput and latency",
            "scope": "Selected full JSON cases only; init, lifecycle and tail latency qualify separately. Both frontends and every selected throughput pair must lead for the written-close target."}
