# list-movies-filtered

A simple Bash script to crawl a web-based Movies directory and list all movie files for a specified year, grouped by subdirectory.

## Repository name

**list-movies-filtered**

## Description

A command‑line tool written in Bash that fetches directory listings from a web server’s autoindex (e.g., `?dir=Movies/2020`), discovers all subdirectories for a given year, and prints the full URLs of `.mkv`, `.mp4`, and `.avi` movie files.

## Usage

```bash
chmod +x list_movies_filtered_v10.sh
./list_movies_filtered_v1.sh "https://example.com/?dir=Movies" 2020
```

### Options

- `-h`, `--help`: Show usage information and exit.

## Features

- Discovers subdirectory IDs automatically
- Handles absolute and relative links, plus plain-text listings
- Deduplicates repeated entries
- Outputs a clean, indented list

## Contributing

Feel free to submit issues or pull requests to improve parsing patterns or add features.
