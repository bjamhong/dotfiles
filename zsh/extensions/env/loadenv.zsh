# Load a local .env.local into the current shell when one exists.
function loadenv() {
  if [[ ! -f .env.local ]]; then
    return 0
  fi

  set -a
  source .env.local
  set +a
}
