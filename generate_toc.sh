#!/bin/sh
# Exit immediately if a command exits with a non-zero status.
set -e

# Get the starting uptime (in seconds) to measure total execution time.
main_timer_start=$(awk '{print $1}' /proc/uptime)

# Debugging switches: set DEBUG to "true" to enable debug logs.
DEBUG="true"
HEX="false"   # Toggle for hex debugging output

# Function to log debug messages if debugging is enabled.
log_debug() {
    [ "$DEBUG" = "true" ] && echo "$@"
}

# Function to print an error message and exit the script.
error_response() {
    local message="$1"
    log_debug "Error: $message"
    exit 1
}

# A timer function to measure execution time of a command.
# It uses /proc/uptime to get the current uptime before and after executing the command.
timer() {
    local start=$(awk '{print $1}' /proc/uptime)
    "$@"   # Execute the passed command(s)
    local end=$(awk '{print $1}' /proc/uptime)
    elapsed=$(echo "$end - $start" | bc)
}

# Check that a folder argument is provided.
if [ -z "$1" ]; then
  error_response "Usage: $0 <folder>"
fi

# Set the folder variable and verify that it is a valid directory.
FOLDER="$1"
if [ ! -d "$FOLDER" ]; then
  error_response "'$FOLDER' is not a valid directory."
fi

# Change directory to the specified folder so that relative file paths work correctly.
cd "$FOLDER" || error_response "Cannot change directory to $FOLDER"

# Get the directory where the script is located
SCRIPT_DIR="$(dirname "$0")"
# Remove the `/www` prefix from the path
URL_PATH="${SCRIPT_DIR#/www}"

# Define filenames and HTML fragments used later in the script.
TOC_FILE="_toc.html"
STYLES_FILE="$URL_PATH/css/_styles.css"
LINK_STYLES="<link type=\"text/css\" rel=\"stylesheet\" href=\"$STYLES_FILE\"/>"
JS_FILE="$URL_PATH/js/_script.js"
SCRIPT="<script type=\"text/javascript\" src=\"$JS_FILE\"></script>"
META='<meta name="viewport" content="width=device-width, initial-scale=1"/>'
DARK_TOGGLE='<button id="dark-toggle">🌙</button>'
BREADCRUMB_HOME="../../../../"
BREADCRUMB_BOOK="../"
TOC_CONTENT=""

# Global variable for storing file-to-title mappings.
# Each mapping line is in the format: filename|||title
TITLE_MAP=""

#####################################
# Detect and extract helper functions
#####################################

# Detect an existing CSS file by listing *.css files and returning the first result.
detect_css_file() {
  ls *.css 2>/dev/null | head -n 1
}

# Detect a TOC source file. This function checks for commonly used filenames.
detect_toc_source() {
  if [ -f "toc01.html" ]; then
    echo "toc.xhtml"
  elif [ -f "nav.xhtml" ]; then
    echo "nav.xhtml"
  elif [ -f "toc.ncx" ]; then
    echo "toc.ncx"
  else
    echo ""
  fi
}

# Detect a cover page, if one exists. This also handles extracting the cover from content.opf.
detect_cover_page() {
  if [ -f "cover.html" ]; then
    echo "cover.html"
  elif [ -f "cover.xhtml" ]; then
    echo "cover.xhtml"
  elif [ -f "content.opf" ]; then
    # Extract the cover id from content.opf using awk.
    COVER_ID=$(awk -F'<meta name="cover" content="|"' '/<meta name="cover"/ {print $2}' content.opf)
    if [ -n "$COVER_ID" ]; then
      # Use the cover id to extract the cover file name.
      awk -F'id="'$COVER_ID'" href="|"' '/id="'$COVER_ID'"/ {print $2}' content.opf
    fi
  fi
}

# Extract an ordered list of HTML files.
# If a TOC source is available, extract file names from its <a href=""> tags;
# otherwise, list all HTML files alphabetically.
extract_ordered_files() {
  local toc_source="$1"
  if [ "$toc_source" = "toc01.html" ]; then
    sed -n 's/.*<a href="\([^"]*\)".*/\1/p' "$toc_source" | cut -d '#' -f 1 | grep -E '\.html|\.xhtml' | tr '\n' ' '
  elif [ "$toc_source" = "nav.xhtml" ]; then
    awk -F'<a href="|"' '/<a href="/ {print $2}' "$toc_source" | grep -E '\.html|\.xhtml' | tr '\n' ' '
  elif [ "$toc_source" = "toc.ncx" ]; then
    awk -F'<content src="|"' '/<content src="/ {print $2}' "$toc_source" | grep -E '\.html|\.xhtml' | tr '\n' ' '
  else
    ls *.html *.xhtml 2>/dev/null | sort
  fi
}

#####################################
# TOC and Navigation Generation
#####################################

# Generate TOC content and build the TITLE_MAP with pretty formatting.
generate_toc() {
  local files="$1"
  # Start the unordered list with a newline.
  # Note: The string is built normally; later we convert it so the "\n" become actual newlines.
  local toc_content="<ul>"
  local strip_anchor=""
  local title=""

  # Loop over each file to build TOC content and mapping.
  for file in $files; do
    # Skip the TOC file to prevent self-inclusion.
    if [ "$file" != "$TOC_FILE" ]; then
      # Remove any anchor (fragment) from the file name.
      strip_anchor=$(echo "$file" | cut -d '#' -f 1)
      # Extract the title from the HTML file (first occurrence of <title> tag).
      title=$(awk -F'<title>|</title>' '/<title>/ {print $2; exit}' "$strip_anchor")
      # If no title is found, default to the file name.
      [ -z "$title" ] && title="$file"
    else
      # Default title for the TOC file itself.
      title="Table of Contents"
    fi

    # Append a mapping line (using literal "\n" which will be converted later).
    TITLE_MAP="${TITLE_MAP}${file}|||${title}\n"

    # Append the formatted list item with indentations and newlines.
    toc_content="${toc_content}<li><a href='$file'>$title</a></li>"
  done

  # Close the unordered list.
  toc_content="${toc_content}</ul>"

  # Convert the TOC string: change literal "\n" sequences into actual newlines.
  TOC_CONTENT=$(printf "%b" "$toc_content")

  # Debug output: print the TITLE_MAP
  echo "TITLE_MAP:"
  printf "%b" "$TITLE_MAP"
  #echo
  #printf "%b" "$TITLE_MAP" | od -c

  # Write the TITLE_MAP to the file "map" (again converting escape sequences).
  printf "%b" "$TITLE_MAP" > map

  # Debug output: show the final TOC_CONTENT.
  echo "TOC_CONTENT:"
  printf "%b" "$toc_content"
}

# Create the TOC HTML file using the generated TOC content.
create_toc_file() {
  local toc_content="$1"
  cat > "$TOC_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>Table of Contents</title>
</head>
<body>
  <h1>Table of Contents</h1>
  $toc_content
</body>
</html>
EOF
}

# Generate breadcrumb navigation HTML for a given page title.
# Uses global variables for home and book links if available.
generate_breadcrumbs() {
  local current_title="$1"
  local breadcrumbs=""

  # Add a Home link if defined.
  if [ -n "$BREADCRUMB_HOME" ]; then
    breadcrumbs="<a href=\"$BREADCRUMB_HOME\">Home</a><span></span>"
  fi

  # Add a Book link if defined.
  if [ -n "$BREADCRUMB_BOOK" ]; then
    breadcrumbs="${breadcrumbs}<a href=\"$BREADCRUMB_BOOK\">Book</a><span></span>"
  fi

  # Append the current page title (not a link).
  breadcrumbs="${breadcrumbs}<span>${current_title}</span>"

  echo "$breadcrumbs"
}

# Helper function to look up a title from the TITLE_MAP for a given file.
lookup_title() {
  local file="$1"
  # Use printf to interpret the escape sequences in TITLE_MAP, then grep for the matching line.
  printf "%b" "$TITLE_MAP" | grep "^$file|||"
}

# Add navigation blocks (Previous, Contents, Next links) to each HTML file.
# The TITLE_MAP is used to determine page titles.
add_navigation() {
  local files="$1"
  local prev=""
  local curr=""
  # A gap div to create vertical spacing for the navigation bar.
  local gap="<div style=\"height: 70px;\"></div>"
  # The content to insert between </head> and <body> (includes CSS link, meta tag, and gap).
  local between="$LINK_STYLES$META</head>"

  # Loop over each file in the list.
  for next in $files; do
    echo "Previous: $prev   Current: $curr   Next: $next"
    # Remove any fragment (anchor) from the filename.
    local strip_anchor=$(echo "$next" | cut -d '#' -f 1)

    # Only process if there is a current file and it's different from the next file.
    if [ -n "$curr" ] && [ "$strip_anchor" != "$curr" ]; then
      echo "Curr: $curr"
      # Lookup the title mapping for the current file.
      local mapping_line=$(printf "%b" "$TITLE_MAP" | grep "^$curr|||")
      echo "Mapping Line: $mapping_line"

      # Extract the title using the "|||" delimiter.
      local current_title=$(echo "$mapping_line" | cut -d '|' -f 4)
      [ -z "$current_title" ] && current_title="$curr"
      echo "Current Title: $current_title"

      # Generate breadcrumbs for the current page.
      local breadcrumbs=$(generate_breadcrumbs "$current_title")

      # Build the navigation HTML block.
      local nav_block="<div class=\"navigation\">"
      nav_block="${nav_block}<div class=\"breadcrumbs\">$breadcrumbs</div>"
      nav_block="${nav_block}<div class=\"page-turning\">"
      if [ -n "$prev" ]; then
        nav_block="${nav_block}<span><a href=\"$prev\">Previous</a></span>"
      else
        nav_block="${nav_block}<span class=\"isDisabled\"><a href=\"#\" aria-disabled=\"true\">Previous</a></span>"
      fi
      nav_block="${nav_block}<span><a href=\"$TOC_FILE\">Contents</a></span>"
      [ -n "$next" ] && nav_block="${nav_block}<span><a href=\"$next\">Next</a></span>"
      nav_block="${nav_block}</div>$DARK_TOGGLE"
      nav_block="${nav_block}</div>"

      # Combine the head insertion block with the navigation block and the JavaScript tag.
      local rep="${gap}${nav_block}${SCRIPT}"
      # Use sed to search for the pattern </head> followed by any whitespace and <body>
      # and replace it with our custom navigation block.
      sed -i -e ":a;N;\$!ba;s|</head>[ \t\r\n]*\(<body[^>]*>\)|${between}\1${rep}|g" "$curr"

      # Set the previous file to the current one for navigation purposes.
      prev="$curr"
    fi

    # Update current file to the stripped file name (without anchor).
    curr="$strip_anchor"
  done

  # Process the final file in the list.
  if [ -n "$curr" ]; then
    echo "Previous: $prev   Current: $curr"
    local mapping_line=$(printf "%b" "$TITLE_MAP" | grep "^$curr|||")
    echo "mapping line: $mapping_line"

    local current_title=$(echo "$mapping_line" | cut -d '|' -f 4)
    [ -z "$current_title" ] && current_title="$curr"
    echo "Current Title: $current_title"

    local breadcrumbs=$(generate_breadcrumbs "$current_title")

    local nav_block="<div class=\"navigation\">"
    nav_block="${nav_block}<div class=\"breadcrumbs\">$breadcrumbs</div>"
    nav_block="${nav_block}<div class=\"page-turning\">"
    [ -n "$prev" ] && nav_block="${nav_block}<span><a href=\"$prev\">Previous</a></span>"
    nav_block="${nav_block}<span><a href=\"$TOC_FILE\">Contents</a></span>"
    [ -n "$next" ] && nav_block="${nav_block}<span class=\"isDisabled\"><a href=\"#\" aria-disabled=\"true\">Next</a></span>"
    nav_block="${nav_block}</div>$DARK_TOGGLE"
    nav_block="${nav_block}</div>"

    local rep="${gap}${nav_block}${SCRIPT}"
    sed -i -e ":a;N;\$!ba;s|</head>[ \t\r\n]*\(<body[^>]*>\)|${between}\1${rep}|g" "$curr"
  fi
}

#####################################
# Main Execution Flow
#####################################

# Log the script start.
log_debug "Generate TOC Script Started"

# Detect any existing CSS file (if one exists).
CSS_FILE=$(detect_css_file)

# Show paths to CSS and JavaScript files.
echo "Styles file located: $STYLES_FILE"
echo "Javascript file located: $JS_FILE"

# Determine the TOC source file (if available) and extract ordered HTML files.
TOC_SOURCE=$(detect_toc_source)
HTML_FILES=$(extract_ordered_files "$TOC_SOURCE")

# Ensure the TOC file is included in the list so it gets a navigation block.
HTML_FILES="$TOC_FILE $HTML_FILES"

# If a cover page exists, add it to the beginning of the file list.
#COVER_PAGE=$(detect_cover_page)
#[ -n "$COVER_PAGE" ] && HTML_FILES="$COVER_PAGE $HTML_FILES"

# Generate the TOC content and build the TITLE_MAP.
generate_toc "$HTML_FILES"

# Create the TOC HTML file.
create_toc_file "$TOC_CONTENT"
echo "TOC generated at: $TOC_FILE"

# Add navigation blocks to all HTML files and measure the time taken.
timer add_navigation "$HTML_FILES"
log_debug "Elapsed Time (add_navigation): ${elapsed}s"
echo "Navigation added to HTML files."

# Calculate and log the total elapsed execution time.
main_timer_stop=$(awk '{print $1}' /proc/uptime)
all_time=$(echo "$main_timer_stop - $main_timer_start" | bc)
log_debug "Total Elapsed Time: ${all_time}s"
