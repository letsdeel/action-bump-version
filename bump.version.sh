#!/bin/bash -x
# script to bump version automatically
# require login to aws codeartifact

if [ ! -f ./package.json ]
then
	echo "file package.json does not exist"
	exit -1
fi
namespace=$(jq -r ".name" package.json | tr -d "@" | awk -F/ '{print $1}')
package_name=$(jq -r ".name" package.json | tr -d "@" | awk -F/ '{print $2}')
fullname="@${namespace}/${package_name}"
saved=$IFS
# get local package version
IFS='.' read -r -a splitversion <<< "$(jq -r .version ./package.json)"
IFS=$saved

major=${splitversion[0]}
minor=${splitversion[1]}
patch=${splitversion[2]}

# support both cli and drone pipeline
if [ -z ${CI_COMMIT_BRANCH+x} ]
then
	branch=$(git branch --show-current)
else
	branch=${CI_COMMIT_BRANCH}
fi

# get version from registry according to branch

if [ "${branch}" == "dev" ] || [ "${branch}" == "master" ]
then
	last_minor=$(aws codeartifact list-package-versions \
		--domain npm \
		--repository npm-dev \
		--format npm \
		--package $package_name \
		--namespace $namespace | jq -r ".versions[].version" | \
		grep "^${major}" | \
		sort -V | \
		awk -F. '{print $2}' | \
		tail -1)
	echo $last_minor
	if [ -z $last_minor ]
	then
		echo "major version ${major}.*.* does not exist in registry."
		echo "cannot bump minor."
		echo "have you changed version manually?"
		exit -1
	else
		echo "bumping minor"
		next_minor=$((last_minor+1))
		# bunp explicit version
		npm version "${major}.${next_minor}.0" --git-tag-version=false --commit-hooks=false --allow-same-version -m "[CI SKIP] Automatically bumped version to %s" --force
	fi
else
	last_patch=$(aws codeartifact list-package-versions \
		--domain npm \
		--repository npm-dev \
		--format npm \
		--package $package_name \
		--namespace $namespace | \
		jq -r ".versions[].version" | \
		grep "^${major}.${minor}." | \
		sort -V | \
		awk -F. '{print $3}' | \
		tail -1)
	if [ -z $last_patch ]
	then
		echo "minor version ${major}.${minor}.* does not exist in registry."
		echo "cannot bump patch."
		echo "have you changed version manually?"
		exit -1
	else
		echo "bumping patch"
		next_patch=$((last_patch+1))
		# bump explicit version
		npm version "${major}.${minor}.${next_patch}" --git-tag-version=false --commit-hooks=false --allow-same-version -m "[CI SKIP] Automatically bumped version to %s" --force
	fi
fi

