#!/usr/bin/env bash
set -euo pipefail

# Registers your local signing pubkey with GitHub so commits show as Verified.
# Requires one interactive OAuth step unless gh already has write:gpg_key.

readonly EMAIL="${GPG_SIGNING_EMAIL:-youwenshao@gmail.com}"
readonly TITLE="${GPG_KEY_TITLE:-MonoClaw signing}"
readonly KEY_FILE="${HOME}/.gnupg/${EMAIL//[@.]/_}-github-signing.pub.asc"

mkdir -p "${HOME}/.gnupg"
export GPG_TTY="${GPG_TTY:-$(tty)}"

if [[ ! -f "${KEY_FILE}" ]]; then
  gpg --armor --export "${EMAIL}" >"${KEY_FILE}"
fi

echo "Public key: ${KEY_FILE}"
gpg --show-keys --with-fingerprint "${KEY_FILE}" || true

echo
echo "Refreshing GitHub CLI OAuth scopes (opens browser / device flow if needed)..."
gh auth refresh -h github.com -s write:gpg_key -s read:gpg_key

echo
echo "Uploading GPG public key to GitHub..."
gh gpg-key add "${KEY_FILE}" -t "${TITLE}"

echo
echo "Done. List keys on GitHub:"
gh gpg-key list
