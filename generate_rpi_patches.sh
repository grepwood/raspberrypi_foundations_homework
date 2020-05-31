#!/usr/bin/env bash
set -euo pipefail
#set -x

function determine_kernel_birthdate {
	local kernel_version=${1}
	local kernel_regex=$(echo ${kernel_version} | sed 's/\./\\\./g')
	set +eo pipefail
	local kernel_birthdate=$(curl -L https://cdn.kernel.org/pub/linux/kernel/v5.x 2>/dev/null | grep ${kernel_regex}\\.tar\\.gz | sed 's/^.*>\s*//' | cut -d ' ' -f 1,2 | date -d - "+%s")
	set -eo pipefail
	echo ${kernel_birthdate}
}

function determine_closest_match_from_rpi_to_vanilla {
	local branch=${2}
	local rpi_branch=${3}
	pushd linux-rpi-${branch} >&2
	local kernel_birthdate=${1}
	local temp=0
	local smallest=9223372036854775807
	local number=0
	local best_i=0
#	set +x
	for i in $(git log --no-merges --date=format:'%s' ${rpi_branch} | grep ^Date: | awk '{print $2}'); do
		temp=$((${i} - ${kernel_birthdate}))
		if [ ${temp} -lt 0 ]; then
			number=$((${temp} * -1))
			if [ ${number} -lt ${smallest} ]; then
				smallest=${number}
				best_i=${i}
			fi
		fi
	done
#	set -x
	popd >&2
	echo "${best_i}"
}

function fetch_commit_from_timestamp {
	local precious_timestamp=${1}
	local branch=${2}
	local rpi_branch=${3}
	pushd linux-rpi-${branch} >&2
		local commit_id=$(git log --no-merges --date=format:'%s' ${rpi_branch} | grep -B2 ^Date:\s*${precious_timestamp}$ | grep ^commit | awk '{print $2}')
		set +e
		git checkout ${commit_id}
		local x=$?
		echo "git checkout returned: ${x}"
		set -e
	popd >&2
}

function get_pristine_state {
	local branch=${1}
	pushd linux-rpi-${branch} >&2
		local pristine_state=$(git rev-parse HEAD | grep -E ^[0-9a-f]*$)
	popd >&2
	echo ${pristine_state}
}

function restore_pristine_state {
	local pristine_state=${1}
	local branch=${2}
	pushd linux-rpi-${branch} >&2
		set +e
		git checkout ${pristine_state}
		local x=$?
		echo "git checkout returned: ${x}"
		set -e
	popd >&2
}

function strip_kernels_from_hidden_entities {
	local kernel_version=${1}
	local branch=${2}
	tar -cp $(find linux-${kernel_version} -name ".*") > hidden-${kernel_version}.tar
	rm -rf $(find linux-${kernel_version} -name ".*")
	tar -cp $(find linux-rpi-${branch} -name ".*") > hidden-${branch}.tar
	rm -rf $(find linux-rpi-${branch} -name ".*")
}

function restore_hidden_entities {
	local kernel_version=${1}
	local branch=${2}
	tar -xf hidden-${kernel_version}.tar
	tar -xf hidden-${branch}.tar
}

function rtfm {
	echo "Usage: ${1} command [kernel_version]"
	echo "Commands:"
	printf "\tclean - removes work artifacts\n"
	printf "\t make - creates a kernel patch for specified version\n"
	return 1
}

function cleanup {
	rm -rf output
}

function main {
	if [ $# -lt 1 ]; then
		rtfm ${0}
	fi
	local mode=${1}
	if [ ${mode} = "clean" ]; then
		cleanup
		return 0
	fi
	if [ ${mode} = "make" ]; then
		if [ $# -lt 2 ]; then
			rtfm ${0}
		fi
	else
		rtfm ${0}
	fi
	mkdir output
	pushd output >&2
	local kernel_version=${2}
	local branch=$(echo ${kernel_version} | cut -d '.' -f 1,2)
	local rpi_branch="rpi-${branch}.y"
	git clone -b ${rpi_branch} https://github.com/raspberrypi/linux.git linux-rpi-${branch}
	wget https://cdn.kernel.org/pub/linux/kernel/v5.x/linux-${kernel_version}.tar.xz
	tar -xf linux-${kernel_version}.tar.xz
	rm -f linux-${kernel_version}.tar.xz
	local kernel_birthdate=$(determine_kernel_birthdate ${kernel_version})
	local rpi_timestamp=$(determine_closest_match_from_rpi_to_vanilla ${kernel_birthdate} ${branch} ${rpi_branch})
	local pristine_state=$(get_pristine_state ${branch})
	local rpi_commit=$(fetch_commit_from_timestamp ${rpi_timestamp} ${branch} ${rpi_branch})
#	set +x
	strip_kernels_from_hidden_entities ${kernel_version} ${branch}
#	set -x
	set +e
	diff -Naur linux-${kernel_version} linux-rpi-${branch} > linux-${kernel_version}-rpi.patch
	if [ $? -eq 2 ]; then
		echo "Diff encountered errors."
		return 2
	fi
	set -e
	restore_hidden_entities ${kernel_version} ${branch}
	restore_pristine_state ${pristine_state} ${branch}
	popd >&2
	echo "Finished"
}

main $@
