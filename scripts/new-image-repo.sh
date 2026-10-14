#!/bin/sh
# Usage: new-image-repo.sh [-n] <name> [description]
#
# Create github.com/daemonless/<name> with the build workflow already on main,
# so the first contributor PR gets CI (build + dbuild lint). A PR that adds
# the workflow itself runs nothing: node-red #1, versitygw #1.
#
# Pushes only README.md and .github/workflows/build.yaml, with [skip ci]: no
# image is built and no ghcr package is made. The image's first push comes
# from GitHub CI when its files land.
#
#   -n   show what would be done, change nothing
set -eu

ORG=daemonless
dry=
if [ "${1:-}" = "-n" ]; then
    dry=1
    shift
fi
name=${1:-}
desc=${2:-}

if [ -z "$name" ] || [ "$name" = "-h" ] || [ "$name" = "--help" ]; then
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi
case $name in
    *[!a-z0-9-]* | -* | *-)
        echo "error: '$name' -- lowercase letters, digits and dashes only" >&2
        exit 2
        ;;
esac

if gh repo view "$ORG/$name" >/dev/null 2>&1; then
    echo "error: $ORG/$name already exists" >&2
    exit 1
fi

# The workflow dbuild init --github writes, from dbuild main.
workflow=$(gh api -H "Accept: application/vnd.github.raw" \
    "repos/$ORG/dbuild/contents/dbuild/templates/github-workflow.yaml" |
    sed "s/{{ name }}/$name/")
case $workflow in
    *"image_name: $name"*) ;;
    *)
        echo "error: could not read the workflow template from $ORG/dbuild" >&2
        exit 1
        ;;
esac

echo "Repository:  $ORG/$name (public)"
echo "Description: ${desc:-(none -- sync-repo-metadata.py fills it from compose.yaml later)}"
echo "Homepage:    https://daemonless.io/images/$name/"
echo "On main:     README.md, .github/workflows/build.yaml"
if [ -n "$dry" ]; then
    echo
    echo "Dry run: nothing created. The workflow:"
    echo "$workflow"
    exit 0
fi

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo
echo "Creating the repository"
gh repo create "$ORG/$name" --public \
    --description "$desc" \
    --homepage "https://daemonless.io/images/$name/"

echo "Writing the workflow"
cd "$work"
git init -q -b main
mkdir -p .github/workflows
printf '%s\n' "$workflow" > .github/workflows/build.yaml
printf '# %s\n' "$name" > README.md
git add README.md .github/workflows/build.yaml
git commit -q -m "ci: the build workflow, before the image [skip ci]"

echo "Pushing to main"
git remote add origin "https://github.com/$ORG/$name.git"
git push -q -u origin main

echo
echo "Done: https://github.com/$ORG/$name"
echo "A contributor's PR now runs build + lint. A first-time contributor's"
echo "run waits for 'Approve and run' on the PR."
