#!/usr/bin/env bash
# list_movies_filtered_v14.sh
# Improved subdir detection for path-style indexes that use relative hrefs like "11092020/"

set -euo pipefail
IFS=$'\n\t'

print_help() {
  cat <<- EOF
Usage: $(basename "$0") [OPTIONS] BASE_URL YEAR

Options:
  -h, --help    Show this help message and exit
  -q            Force query-mode (use '?dir=Movies/...' style URLs)

Arguments:
  BASE_URL      Base Movies URL (examples):
                  "https://tokyo.saymyname.website/?dir=Movies"
                  "https://berlin.saymyname.website/Movies/"
  YEAR          Four-digit year to filter (e.g. 2025)
EOF
}

# Parse options
FORCE_QUERY=0
while [[ ${1:-} =~ ^- ]]; do
  case "$1" in
    -h|--help) print_help; exit 0 ;;
    -q) FORCE_QUERY=1; shift ;;
    --) shift; break ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# Arg count
if [ $# -ne 2 ]; then
  echo "Error: Invalid arguments. Use --help for usage." >&2
  exit 1
fi

BASE_ARG="$1"
YEAR="$2"

# Basic validation of year (four digits)
if ! [[ "$YEAR" =~ ^[0-9]{4}$ ]]; then
  echo "Error: YEAR must be a four-digit year (e.g. 2025)." >&2
  exit 1
fi

# Extract host (protocol + domain)
if [[ "$BASE_ARG" =~ ^(https?://[^/]+) ]]; then
  HOST="${BASH_REMATCH[1]}"
else
  echo "Error: Invalid URL (need protocol and host): $BASE_ARG" >&2
  exit 1
fi

# Decide mode: query-style (/?dir=Movies/...) or path-style (/Movies/...)
MODE=""
if [ "$FORCE_QUERY" -eq 1 ]; then
  MODE="query"
else
  if [[ "$BASE_ARG" == *"?dir="* ]]; then
    MODE="query"
  elif [[ "$BASE_ARG" == *"/Movies"* ]]; then
    MODE="path"
  else
    # probe the homepage (best-effort)
    if PAGE="$(curl -fsSL "${BASE_ARG%/}/" 2>/dev/null || true)"; then
      if printf '%s\n' "$PAGE" | grep -qE '\?dir=Movies/' ; then
        MODE="query"
      elif printf '%s\n' "$PAGE" | grep -qE '/Movies/' ; then
        MODE="path"
      else
        MODE="query"
      fi
    else
      MODE="query"
    fi
  fi
fi

# Build LIST_URL
if [ "$MODE" = "query" ]; then
  LIST_URL="${HOST}/?dir=Movies/${YEAR}"
else
  LIST_URL="${HOST%/}/Movies/${YEAR}/"
fi

echo
printf "Mode: %s\n" "$MODE"
printf "Movie - %s\n\n" "$YEAR"

# Download the listing page once (if accessible)
PAGE_ROOT="$(curl -fsSL "$LIST_URL" 2>/dev/null || true)"

# --- Extract numeric subdirectory IDs robustly ---
declare -A subdirs_map=()

if [ "$MODE" = "query" ]; then
  # get href values, look for ?dir=Movies/YEAR/<id>
  mapfile -t HREFS < <(printf "%s\n" "$PAGE_ROOT" | grep -oP '(?<=href=")[^"]+' 2>/dev/null || true)
  for h in "${HREFS[@]}"; do
    # examples: ?dir=Movies/2025/11092020, /?dir=Movies/2025/11092020, Movies/2025/11092020
    if [[ "$h" =~ ^\?dir=Movies/${YEAR}/([0-9]+)/?$ ]] || \
       [[ "$h" =~ ^/?dir=Movies/${YEAR}/([0-9]+)/?$ ]] || \
       [[ "$h" =~ ^/?Movies/${YEAR}/([0-9]+)/?$ ]]; then
      id="${BASH_REMATCH[1]}"
      subdirs_map["$id"]=1
    fi
  done
else
  # path mode
  mapfile -t HREFS < <(printf "%s\n" "$PAGE_ROOT" | grep -oP '(?<=href=")[^"]+' 2>/dev/null || true)
  for h in "${HREFS[@]}"; do
    # strip any trailing slash for matching
    h_noslash="${h%/}"
    # case: href="11092020/"  => plain numeric relative
    if [[ "$h_noslash" =~ ^([0-9]+)$ ]]; then
      subdirs_map["${BASH_REMATCH[1]}"]=1
      continue
    fi
    # case: href="./11092020" or href="./11092020/"
    if [[ "$h_noslash" =~ ^\./([0-9]+)$ ]]; then
      subdirs_map["${BASH_REMATCH[1]}"]=1
      continue
    fi
    # case: href="/Movies/2025/11092020/" or "Movies/2025/11092020/"
    if [[ "$h_noslash" =~ ^/?Movies/${YEAR}/([0-9]+)$ ]]; then
      subdirs_map["${BASH_REMATCH[1]}"]=1
      continue
    fi
    # case: sometimes directory listings include the full path without year prefix,
    # e.g., href="/2025/11092020/"  (rare) -> match /YEAR/ID
    if [[ "$h_noslash" =~ ^/?${YEAR}/([0-9]+)$ ]]; then
      subdirs_map["${BASH_REMATCH[1]}"]=1
      continue
    fi
  done
fi

# Convert map keys to array sorted
SUBDIRS=()
for k in "${!subdirs_map[@]}"; do SUBDIRS+=("$k"); done
IFS=$'\n' SUBDIRS=($(sort -n <<<"${SUBDIRS[*]:-}")) || true
unset IFS

if [ ${#SUBDIRS[@]} -eq 0 ]; then
  printf "(No numeric subdirectory IDs found under %s)\n\n" "$LIST_URL"
fi

# Crawl each subdirectory (or LIST_URL itself) and list files
if [ ${#SUBDIRS[@]} -gt 0 ]; then
  TARGET_DIRS=("${SUBDIRS[@]}")
else
  TARGET_DIRS=("_LISTROOT_")
fi

for ID in "${TARGET_DIRS[@]}"; do
  if [ "$ID" = "_LISTROOT_" ]; then
    SUB_URL="$LIST_URL"
    BASE_DIR_PATH="Movies/${YEAR}"
  else
    if [ "$MODE" = "query" ]; then
      SUB_URL="${HOST}/?dir=Movies/${YEAR}/${ID}"
      BASE_DIR_PATH="Movies/${YEAR}/${ID}"
    else
      SUB_URL="${HOST%/}/Movies/${YEAR}/${ID}/"
      BASE_DIR_PATH="Movies/${YEAR}/${ID}"
    fi
  fi

  printf -- "- %s\n" "$SUB_URL"

  PAGE="$(curl -fsSL "$SUB_URL" 2>/dev/null || true)"

  # Extract file candidates (hrefs or visible filenames) that end with video extensions
  mapfile -t HREFS < <(printf "%s\n" "$PAGE" | grep -oP '(?<=href=")[^"]+' 2>/dev/null || true)

  declare -A seen=()

  # Also check for visible text filenames (e.g., plain anchors where href missing or text nodes).
  # We'll look for occurrences of .mkv/.mp4/.avi in the page as a fallback.
  mapfile -t INLINE_FILES < <(printf "%s\n" "$PAGE" | grep -oE '[^/<>[:space:]]+\.(mkv|mp4|avi)' 2>/dev/null || true)

  # Process hrefs first
  for h in "${HREFS[@]}"; do
    # skip parent directory links
    [[ "$h" == "../" || "$h" == "/" || "$h" == "" ]] && continue

    # If href points to a file with extension, use it directly
    if [[ "$h" =~ \.(mkv|mp4|avi)(\?.*)?$ ]]; then
      # normalise into URL
      if [[ "$h" =~ ^https?:// ]]; then
        URL="$h"
      elif [[ "$h" =~ ^\?dir= ]]; then
        URL="${HOST}/${h}"
      elif [[ "$h" =~ ^/ ]]; then
        URL="${HOST}${h}"
      elif [[ "$h" =~ ^Movies/ ]]; then
        URL="${HOST}/${h}"
      else
        # relative filename -> attach to base dir
        if [ "$MODE" = "query" ]; then
          URL="${HOST}/?dir=${BASE_DIR_PATH}/${h}"
        else
          URL="${HOST%/}/${BASE_DIR_PATH}/${h}"
        fi
      fi

      seen["$URL"]=1
      continue
    fi

    # If href is something that points to a directory, ignore here (files will be found when crawling that subdir)
    # Otherwise if href looks like a query to a file e.g. ?dir=Movies/2025/ID/file.mp4
    if [[ "$h" =~ \?dir=.*\.(mkv|mp4|avi) ]]; then
      URL="${HOST}/${h}"
      seen["$URL"]=1
      continue
    fi
  done

  # Process inline filename matches (fallback)
  for f in "${INLINE_FILES[@]}"; do
    # skip duplicates
    if [[ -n "${seen[$f]:-}" ]]; then
      continue
    fi
    # Build URL relative to base dir
    if [[ "$f" =~ ^https?:// ]]; then
      URL="$f"
    else
      if [ "$MODE" = "query" ]; then
        URL="${HOST}/?dir=${BASE_DIR_PATH}/${f}"
      else
        URL="${HOST%/}/${BASE_DIR_PATH}/${f}"
      fi
    fi
    seen["$URL"]=1
  done

  if [ ${#seen[@]} -eq 0 ]; then
    printf "    (No movie files found)\n\n"
  else
    for url in "${!seen[@]}"; do
      printf "    * %s\n" "$url"
    done
    printf "\n"
  fi
done
