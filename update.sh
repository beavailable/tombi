#!/usr/bin/bash
set -euo pipefail
shopt -s inherit_errexit

# $@: arguments
_curl() {
    local retries
    retries=0
    while true; do
        if curl -sSL --fail-early --fail-with-body --connect-timeout 10 -H "Authorization: Bearer $GITHUB_TOKEN" "$@"; then
            break
        fi
        ((++retries))
        if [[ $retries -ge 3 ]]; then
            return 1
        fi
        sleep $((retries * 5))
    done
}
# $1: version
download_binaries() {
    local f bin
    for f in "tombi-cli-$1-x86_64-unknown-linux-musl.gz" "tombi-cli-$1-aarch64-unknown-linux-musl.gz"; do
        _curl -O "https://github.com/tombi-toml/tombi/releases/download/v$1/$f"
        gzip -d "$f"
        bin="${f%.gz}"
        chmod +x "$bin"
        if [[ "$bin" == tombi-cli-$version-x86_64* ]]; then
            mv "$bin" tombi_amd64
        else
            mv "$bin" tombi_arm64
        fi
    done
    mkdir completions
    ./tombi_amd64 completion bash >completions/tombi
    ./tombi_amd64 completion zsh >completions/_tombi
    ./tombi_amd64 completion fish >completions/tombi.fish
}

read -r version revision <<<$(sed -nE '1s/^\S+ \((\S+)-(\S+)\) .+$/\1 \2/p' debian/changelog)
new_version=''
tags=$(_curl "https://api.github.com/repos/tombi-toml/tombi/tags" | sed -nE 's/^\s+"name": "v(\S+)",$/\1/p')
for tag in $tags; do
    if [[ "$tag" == "$version" ]]; then
        break
    fi
    if dpkg --compare-versions "$tag" gt "$version"; then
        new_version="$tag"
        break
    fi
done

if [[ -n "$new_version" ]]; then
    download_binaries "$new_version" || exit 0
    new_version="$new_version-1"
elif [[ "${TOMBI_FORCE_RELEASE:-}" == 'true' ]]; then
    download_binaries "$version" || exit 0
    new_version="$version-$((revision + 1))"
else
    exit 0
fi

changelog=$(cat debian/changelog)
{
    echo "tombi ($new_version) unstable; urgency=medium"
    echo
    echo '  * New release.'
    echo
    echo " -- beavailable <beavailable@proton.me>  $(date '+%a, %d %b %Y %H:%M:%S %z')"
    echo
    echo "$changelog"
} >debian/changelog

user='github-actions[bot]'
email='41898282+github-actions[bot]@users.noreply.github.com'
git -c user.name="$user" -c user.email="$email" commit -am "Release $new_version" --author "$GITHUB_ACTOR <$GITHUB_ACTOR_ID+$GITHUB_ACTOR@users.noreply.github.com>"
git -c user.name="$user" -c user.email="$email" tag "$new_version" -am "Release $new_version"
git push origin --follow-tags --atomic

git add tombi_* completions
git -c user.name="$user" -c user.email="$email" commit -m 'Add files'

echo "release=true" >>$GITHUB_OUTPUT
