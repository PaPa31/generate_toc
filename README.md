# generate_toc.sh

## Overview

`generate_toc.sh` is a shell script designed to generate a Table of Contents (TOC) for an extracted EPUB container. It ensures the order of HTML files follows the author's intended sequence by extracting data from existing TOC sources like `nav.xhtml` or `toc.ncx`. Additionally, it enhances navigation by injecting a navigation bar and styling for improved readability.

## Features

- Detects existing TOC sources (`nav.xhtml`, `toc.ncx`) to maintain correct order
- Generates a `_toc.html` file containing links to content files
- Adds navigation between files (Previous, Contents, Next)
- Supports a dark mode toggle for better readability
- Injects custom CSS and JavaScript for styling and user interaction
- Detects and includes cover pages if available

## Requirements

- Compatible with **BusyBox ash** shell
- Requires an **extracted EPUB** folder structure
- Runs on **OpenWrt (Backfire 10.03, x86, 2010)**

## Usage

Run the script with the folder containing extracted EPUB contents:

```sh
./generate_toc.sh <folder>
```

### Example
```sh
./generate_toc.sh /path/to/extracted_epub
```

## Output

The script generates the following files:

- `_toc.html` - The generated Table of Contents
- `_styles.css` - Stylesheet for formatting
- `_script.js` - JavaScript file for dark mode toggle

Additionally, all HTML files receive an injected navigation block at the top.

## Navigation Structure

Each HTML file includes a **fixed navigation bar**:

```
[Previous] [Contents] [Next]  🌙 (Dark Mode Toggle)
```

## Implementation Details

1. **Detect TOC Source**
   - Checks for `nav.xhtml` or `toc.ncx` to maintain correct reading order.
   - Falls back to alphabetical sorting if no TOC source is found.

2. **Extract Ordered Files**
   - Retrieves a list of content files, removing anchors (e.g., `file.html#section` → `file.html`).

3. **Generate TOC File**
   - Creates `_toc.html` with extracted file names and titles.

4. **Inject Navigation**
   - Adds a navigation bar (`Previous`, `Contents`, `Next`) to each HTML file.
   - Includes a **dark mode toggle** for better reading in low-light environments.

## Notes

- If a cover page is found (`cover.html`, `cover.xhtml`), it is placed at the start.
- The script is optimized for low-power environments (e.g., **eBox-2300sx** running **OpenWrt Backfire 10.03**).

## License
This script is provided "as is" without warranty. Use at your own risk.

