#!/usr/bin/env bash
# list_movies_filtered_v10.sh
# Usage: list_movies_filtered_v10.sh [--help] "<base_url>?dir=Movies" <year>

set -euo pipefail
IFS=$'\n\t'

print_help() {
  cat <<- EOF
Usage: $(basename "$0") [OPTIONS] BASE_URL YEAR

Options:
  -h, --help    Show this help message and exit

Arguments:
  BASE_URL      Base Movies URL (e.g. "https://site.com/?dir=Movies")
  YEAR          Four-digit year to filter (e.g. 2020)

Example:
  $(basename "$0") "https://tokyo.saymyname.website/?dir=Movies" 2020
EOF
}

# Help flag
if [[ ${1:-} =~ ^(-h|--help)$ ]]; then
  print_help
  exit 0
fi

# Arg count
if [ $# -ne 2 ]; then
  echo "Error: Invalid arguments. Use --help for usage." >&2
  exit 1
fi

BASE_ARG="$1"
YEAR="$2"

# Extract host (e.g. https://tokyo.saymyname.website)
if [[ "$BASE_ARG" =~ ^(https?://[^/]+) ]]; then
  HOST="${BASH_REMATCH[1]}"
else
  echo "Error: Invalid URL: $BASE_ARG" >&2
  exit 1
fi

LIST_URL="${HOST}/?dir=Movies/${YEAR}"

echo
printf "Movie - %s\n\n" "$YEAR"

# Get subdirectories
mapfile -t SUBDIRS < <(
  curl -fsSL "$LIST_URL" |
    grep -oP '(?<=href=")\?dir=Movies/'"$YEAR"'/[0-9]+' |
    sed -E 's|.*/([0-9]+)$|\1|' |
    sort -u
)

# Crawl each subdirectory
for ID in "${SUBDIRS[@]}"; do
  SUB_URL="${HOST}/?dir=Movies/${YEAR}/${ID}"
  echo "- ${SUB_URL}"

  PAGE="$(curl -fsSL "$SUB_URL")"

  # Extract file candidates
  mapfile -t FILES_RAW < <(
    printf "%s\n" "$PAGE" |
    grep -oE '(href=\"[^\"]+\.(mkv|mp4|avi)\"|>[^<]+\.(mkv|mp4|avi)(<|$))' |
    sed -E 's/(href=\"|")(.*?)(\"|>.*)/\2/' |
    sed 's|^/||'
  )

  # Normalize paths and dedupe
  declare -A seen=()
  for F in "${FILES_RAW[@]}"; do
    [[ -z "$F" ]] && continue
    # Determine full URL
    if [[ "$F" =~ ^https?:// ]]; then
      URL="$F"
    elif [[ "$F" =~ ^Movies/${YEAR}/${ID}/ ]]; then
      URL="${HOST}/${F}"
    else
      URL="${HOST}/Movies/${YEAR}/${ID}/${F}"
    fi
    # Print unique
    if [[ -z "${seen[$URL]:-}" ]]; then
      echo "    * $URL"
      seen[$URL]=1
    fi
  done

  # If none printed
  if [ ${#seen[@]} -eq 0 ]; then
    echo "    (No movie files found)"
  fi

  echo
done

