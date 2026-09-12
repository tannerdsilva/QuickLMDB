#!/usr/bin/env bash
#
# verify-consumers.sh — the cross-repo gate (DEBT item 5).
#
# pins each named consumer to THIS QuickLMDB WORKING TREE (a pre-commit
# gate mirrors the tree — the change under test), builds it, and runs its
# suite. the parent change that
# regresses a previously-migrated consumer is caught HERE, not by the next
# consumer migration.
#
# contract with the consumer repos: each consumer resolves QuickLMDB through
# a local path pin (the migration-stage layout uses `.package(path:"../QuickLMDB")`,
# i.e. a staged sibling clone at <consumer>/../QuickLMDB). this script
# resyncs that staged clone from the parent tree — so the consumer builds
# against the PARENT'S CURRENT HEAD, not a stale staged copy.
#
# usage:
#   scripts/verify-consumers.sh [--sync-only] [consumer-dir ...]
#
# default consumers: the migration-stage pair the skeptic audit pinned
# (override with positional args, e.g. a single consumer for a subset).
#
# the Linux leg (wiremand's suite is Linux-targeted) is the same script run
# on the Linux box after pulling — macOS here runs the macOS-capable suites
# and reports wiremand's build status honestly.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_REPO="$(cd "$SCRIPT_DIR/.." && pwd)"

SYNC_ONLY=0
CONSUMERS=()
for arg in "$@"; do
	case "$arg" in
		--sync-only) SYNC_ONLY=1 ;;
		-*)
			echo "unknown flag: $arg" >&2
			echo "usage: verify-consumers.sh [--sync-only] [consumer-dir ...]" >&2
			exit 2
			;;
		*) CONSUMERS+=("$arg") ;;
	esac
done

if [ "${#CONSUMERS[@]}" -eq 0 ]; then
	CONSUMERS=(
		"$HOME/workspace/qlmdb16-migrate-test/pricedb"
		"$HOME/workspace/qlmdb16-migrate-test/wiremand"
	)
fi

command -v rsync >/dev/null 2>&1 || { echo "rsync is required" >&2; exit 2; }

HOST="$(uname -s)"
SKIPPED=0
overall=0

for consumer in "${CONSUMERS[@]}"; do
	echo "=== consumer: $consumer"
	[ -d "$consumer" ] || { echo "MISSING consumer dir: $consumer" >&2; overall=1; continue; }

	# 1. resolve the consumer's QuickLMDB pin (the staged sibling clone)
	local_pin="$consumer/../QuickLMDB"
	pin_dir="$(cd "$consumer/.." && pwd)/QuickLMDB"
	[ -d "$pin_dir" ] || { echo "MISSING pin dir: $pin_dir (consumer must pin QuickLMDB at <consumer>/../QuickLMDB)" >&2; overall=1; continue; }

	# 2. pins to the CURRENT TREE: resync the staged clone from the parent
	#    working tree (build artifacts and debris excluded)
	echo "  syncing $PARENT_REPO -> $pin_dir"
	rsync -a --delete \
		--exclude '.build' \
		--exclude '.swiftpm' \
		--exclude '.DS_Store' \
		"$PARENT_REPO/" "$pin_dir/" || { echo "SYNC FAILED" >&2; overall=1; continue; }

	if [ "$SYNC_ONLY" -eq 1 ]; then
		echo "  synced (--sync-only, no build)"
		continue
	fi

	# 3. build + suite. capture the log so host-platform failures (a
	#    Linux-only consumer on Darwin, e.g. wiremand and its netlink C
	#    target) can be told apart from REAL parent regressions.
	echo "  swift build --build-tests ..."
	build_log="$TMPDIR/qlmdb-gate-build-$(basename "$consumer").log"
	if ! (cd "$consumer" && swift build --build-tests >"$build_log" 2>&1); then
		if [ "$HOST" = "Darwin" ] && grep -Eqi "linux/(netlink|if_|inet|types|sockios)" "$build_log"; then
			echo "SKIPPED (Linux-only consumer on this host): $(basename "$consumer")"
			SKIPPED=1
			continue
		fi
		echo "BUILD FAILED: $consumer" >&2
		tail -15 "$build_log" >&2
		overall=1
		continue
	fi
	echo "  swift test ..."
	test_log="$TMPDIR/qlmdb-gate-test-$(basename "$consumer").log"
	if ! (cd "$consumer" && swift test >"$test_log" 2>&1); then
		echo "TEST FAILED: $consumer" >&2
		tail -15 "$test_log" >&2
		overall=1
		continue
	fi
	# a "green" suite that ran ZERO tests is not a gate — assert a real
	# count. Swift Testing prints `Test run with N tests`; XCTest prints
	# `Executed N test(s)`. prefer the Swift Testing marker (the CLI
	# consumers use it) and fall back to XCTest.
	swiftmarker=$(grep -Eo "Test run with [0-9]+ test" "$test_log" | head -1 || true)
	if [ -n "$swiftmarker" ]; then
		tests_run="$swiftmarker"
	else
		tests_run=$(grep -Eo "Executed [1-9][0-9]* test" "$test_log" | head -1 || true)
	fi
	if [ -z "$tests_run" ] || [ "$tests_run" = "Test run with 0 tests" ]; then
		echo "TEST RUN EMPTY (no tests executed): $consumer" >&2
		overall=1
		continue
	fi
	echo "PASS: $consumer ($tests_run)"
done

echo "=== consumer gate summary: $([ $overall -eq 0 ] && echo ALL PASS || echo FAILURES) ($([ "$SKIPPED" -eq 1 ] && echo '1+ skips (platform, not regression)' || echo 'no skips'))"
exit $overall
