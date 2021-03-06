#!/bin/bash


set -e
# Get the list of tests to run from command line or take all tests from the
# default path
if [[ $# -ne 0 ]] ; then
	TESTS=$@
else
	TESTS=(`ls tests.d/*`)
fi

function finish {
	rm -rf -- "$TMP"
}
trap finish EXIT


export AUTO_TEST='yes'

declare -A TEMPLATES
TEMPLATES[DEBIAN_VERSION]="$(lsb_release -sr)"
TEMPLATES[DEBIAN_VERSION_ENC]="${TEMPLATES[DEBIAN_VERSION]/\//%2F}"
TEMPLATES[DIST_NAME]="$(lsb_release -si)"

# Run tests one by one
for A in ${TESTS[*]} ; do
	echo $A

	# Create temporary directory for storing test's outputs
	export TMP=$(mktemp -d)
	export SUBDIR=${TMP:5}

	EXPECTED_STDOUT=$TMP/expected_stdout
	EXPECTED_STDERR=$TMP/expected_stderr
	REAL_STDOUT=$TMP/real_stdout
	REAL_STDERR=$TMP/real_stderr
	TEMPLATES[CWD]=$TMP
	export XDG_CACHE_HOME=$TMP

	# Extract expected output and real output (by running the test scenario)
	sed -n -e 's/^#o \?\(.*\)$/\1/p' -e 's/^\(Scenario .*\)$/\n\n\1\n\n/p' -e 's/^\(Testcase .*\)$/\n\1\n/p' -- "$A" | sed "s|\$TMP|$TMP|g" | sed "s|\$SUBDIR|$SUBDIR|g" >"$EXPECTED_STDOUT"
	sed -n -e 's/^#e \?\(.*\)$/\1/p' -e 's/^\(Scenario .*\)$/\n\n\1\n\n/p' -e 's/^\(Testcase .*\)$/\n\1\n/p' -- "$A" | sed "s|\$TMP|$TMP|g" | sed "s|\$SUBDIR|$SUBDIR|g" >"$EXPECTED_STDERR"

	for key in "${!TEMPLATES[@]}" ; do
		sed -i "s!%$key%!${TEMPLATES[$key]}!g" $EXPECTED_STDERR
		sed -i "s!%$key%!${TEMPLATES[$key]}!g" $EXPECTED_STDOUT
	done

	bash $A >"$REAL_STDOUT" 2>"$REAL_STDERR" || true

	# Remove messages known to be prone to race conditions
	sed -i '/Opening connection 127\.0\.0\.1:10000/d' "$REAL_STDERR"

	# From output replace any ISO dates
	sed -i 's/20[0-9]\{2\}-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-6][0-9]\.[0-9]\{6\}Z\?/ISODATETIME/g' "$REAL_STDERR"

	# Display differences
	diff -u -- "$EXPECTED_STDERR" "$REAL_STDERR"
	diff -u -- "$EXPECTED_STDOUT" "$REAL_STDOUT"

	rm -rf -- "$TMP"
done

echo 'SUCCESS'

