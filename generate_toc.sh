#!/bin/sh
# Exit immediately if a command exits with a non-zero status.
set -e

#####################################
# Initialization & Debug Functions
#####################################
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

#####################################
# Directory & Path Setup
#####################################
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

# Global variable for storing file-to-title mappings.
TITLE_MAP=""     # Will hold mapping lines: href@title
TOC_CONTENT=""   # Will hold the final TOC HTML content
FILE_LIST=""

#####################################
# Detect and extract helper functions
#####################################
# Detect an existing CSS file by listing *.css files
detect_css_file() {
  ls *.css 2>/dev/null
}

#####################################
# TOC Source Detection
#####################################
# Detect a TOC source file. This function checks for commonly used filenames.
detect_toc_source() {
    if [ -f "nav.xhtml" ]; then
        echo "nav.xhtml"
    elif [ -f "toc.ncx" ]; then
        echo "toc.ncx"
    elif [ -f "toc.xhtml" ]; then
        echo "toc.xhtml"
    else
        echo ""
    fi
}

#####################################
# New Function: Extract TOC Content from Navigation File
#####################################
# This function extracts navigation lines (formatted as "Title - href")
# from a TOC source file (NCX or HTML navigation).
extract_toc_content() {
    local toc_source="$1"
    if [ "$toc_source" = "toc.ncx" ]; then
        # --- NCX Extraction ---
        sed 's/<navPoint/\
<navPoint/g' "$toc_source" | \
        awk 'BEGIN{RS="<navPoint"; ORS="\n"} NR>1{
          pos1=index($0,"<navLabel>"); title="";
          if(pos1>0){
            rest1=substr($0, pos1+length("<navLabel>"));
            pos2=index(rest1,"<text>");
            if(pos2>0){
              rest2=substr(rest1, pos2+length("<text>"));
              pos3=index(rest2,"</text>");
              if(pos3>0) title=substr(rest2,1,pos3-1);
            }
          }
          posC=index($0,"<content"); href="";
          if(posC>0){
            restC=substr($0, posC);
            posS=index(restC,"src=\"");
            if(posS>0){
              restS=substr(restC, posS+length("src=\""));
              posQ=index(restS,"\"");
              if(posQ>0) href=substr(restS,1,posQ-1);
            }
          }
          if(title!="" && href!="") print href "@" title;
        }'
    elif grep -q "<nav" "$toc_source"; then
        # --- HTML Navigation Extraction ---
        if grep -q '<nav[^>]*epub:type="toc"' "$toc_source"; then
            sed 's/<nav/\n<nav/g' "$toc_source" | \
            sed -n '/<nav[^>]*epub:type="toc"[^>]*>/,/<\/nav>/p' | \
            sed 's/<li/\
<li/g' | \
            sed -n 's/.*<a href="\([^"]*\)">\([^<]*\)<\/a>.*/\1@\2/p'
        else
            sed 's/<li/\
<li/g' "$toc_source" | \
            sed -n 's/.*<a href="\([^"]*\)">\([^<]*\)<\/a>.*/\1@\2/p'
        fi
    else
        echo ""
    fi
}

#####################################
# New Function: Generate Mapping and TOC HTML from Extracted Navigation Lines
#####################################
# Input: Lines in the format "Title - href"
# Output: 
#   - TITLE_MAP is built in the format "href@title" (and written to file "map")
#   - TOC_CONTENT is built as an unordered HTML list.
generate_mapping_and_toc() {
    local extracted="$1"
    local toc_content=""
    #TITLE_MAP=""  # Reset mapping
    local prev=""
 
    # Use a here-document so that the while loop runs in the current shell (avoiding subshell issues)
    while IFS='@' read -r href title; do

        # Remove any anchor (fragment) from the file name.
        local strip_anchor=$(echo "$href" | cut -d '#' -f 1)
        # Ignore if filename repeat
        if [ "$prev" != "$strip_anchor" ]; then
          # Append to mapping in the format: href@title (each mapping separated by a newline)
          #TITLE_MAP="${TITLE_MAP}${strip_anchor}@${title}\n"
          # Populate HTML file list
          FILE_LIST="${FILE_LIST}${strip_anchor} "
        fi
        # Append to TOC HTML content
        toc_content="${toc_content}<li><a href='$href'>$title</a></li>"
        prev="$strip_anchor"
    done <<EOF
$extracted
EOF

    #toc_content="${toc_content}</ul>"
    TOC_CONTENT=$(printf "%b" "$toc_content")

    # Debug output: print the TITLE_MAP
    #echo "TITLE_MAP:"
    #printf "%b" "$TITLE_MAP"

    # Optionally, write the mapping to a file named "map"
    #printf "%b" "$TITLE_MAP" > map
}

#####################################
# New Function: Generate TOC from HTML Files
#####################################
# This function is used when no TOC source file is found.
# It scans all HTML files in the directory, extracts the <title> from each,
# and builds the mapping (filename@title) and TOC HTML content.
generate_toc_from_html_files() {
    local files=$(ls *.html *.xhtml 2>/dev/null | sort)
    local toc_content=""
    TITLE_MAP=""
    for file in $files; do
        if [ "$file" = "$TOC_FILE" ]; then
            title="Table of Contents"
        else
            title=$(awk -F'<title>|</title>' '/<title>/ {print $2; exit}' "$file")
            [ -z "$title" ] && title="$file"
        fi
        TITLE_MAP="${TITLE_MAP}${file}@${title}\n"
        toc_content="${toc_content}<li><a href='$file'>$title</a></li>"
    done
    #toc_content="${toc_content}</ul>"
    TOC_CONTENT=$(printf "%b" "$toc_content")

    # Debug output: print the TITLE_MAP
    echo "TITLE_MAP:"
    printf "%b" "$TITLE_MAP"

    printf "%b" "$TITLE_MAP" > map

    FILE_LIST="$files"
}

#####################################
# Create TOC HTML File
#####################################
create_toc_file() {
    local existing_css="$1"
    local toc_content="$2"
    local css_content=""

    # Create <links> as many as css files found
    for file in $existing_css; do
        css_content="${css_content}<link type=\"text/css\" rel=\"stylesheet\" href=\"$file\"/>"
    done

  cat > "$TOC_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>Table of Contents</title>
  $css_content
</head>
<body>
  <h1>Table of Contents</h1>
  <ul class="toc">
    $toc_content
  </ul>
</body>
</html>
EOF
}

# Detect a cover page, if one exists. This also handles extracting the cover from content.opf.
detect_cover_page() {
  for file in "cover.html" "cover.xhtml"; do
    [ -f "$file" ] && echo "$file" && return
  done
  if [ -f "content.opf" ]; then
    COVER_ID=$(awk -F'<meta name="cover" content="|"' '/<meta name="cover"/ {print $2}' content.opf)
    [ -n "$COVER_ID" ] && awk -F'id="'$COVER_ID'" href="|"' '/id="'$COVER_ID'"/ {print $2}' content.opf
  fi
}

# Generate breadcrumb navigation HTML for a given page title.
# Uses global variables for home and book links if available.
generate_breadcrumbs() {
  local current_title="$1"
  local breadcrumbs=""

  # Add a Home link if defined.
  if [ -n "$BREADCRUMB_HOME" ]; then
    breadcrumbs="<span><a href=\"$BREADCRUMB_HOME\">Home</a></span>"
  fi

  # Add a Book link if defined.
  if [ -n "$BREADCRUMB_BOOK" ]; then
    breadcrumbs="${breadcrumbs}<span><a href=\"$BREADCRUMB_BOOK\">Book</a></span>"
  fi

  # Append the current page title (not a link).
  breadcrumbs="${breadcrumbs}<span>${current_title}</span>"
  breadcrumbs="<div class=\"centerward\">${breadcrumbs}</div>"

  echo "$breadcrumbs"
}

# Helper function to look up a title from the TITLE_MAP for a given file.
lookup_title() {
  local file="$1"
  # Use printf to interpret the escape sequences in TITLE_MAP, then grep for the matching line.
  printf "%b" "$TITLE_MAP" | grep "^$file@"
}

#####################################
# (Existing) Navigation Insertion Function
#####################################
# This function uses TITLE_MAP (in href@title format) to add Previous/Next navigation blocks to each HTML file.
add_navigation() {
  local files="$@"
  local prev=""
  local curr=""
  # A gap div to create vertical spacing for the navigation bar.
  local gap="<div style=\"height: 80px;\"></div>"
  # The content to insert between </head> and <body> (includes CSS link and meta tag).
  local between="$LINK_STYLES$META</head>"

  # Loop over each file in the list.
  for next in $files; do
    echo "Previous: $prev   Current: $curr   Next: $next"
    # Remove any fragment (anchor) from the filename.
    local strip_anchor=$(echo "$next" | cut -d '#' -f 1)

    # Only process if there is a current file and it's different from the next file.
    if [ -n "$curr" ] && [ "$strip_anchor" != "$curr" ]; then
      echo "Curr: $curr"
      # Lookup the title for curr from TITLE_MAP (format: filename@title)
      local mapping_line=$(printf "%b" "$TITLE_MAP" | grep "^$curr#*.*@")
      echo "Mapping Line: $mapping_line"

      # Extract the title using the "@" delimiter.
      local current_title=$(echo "$mapping_line" | head -n 1 | cut -d '@' -f 2)
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
      nav_block="${nav_block}<span><a href=\"$next\">Next</a></span>"
      nav_block="${nav_block}</div>$DARK_TOGGLE"
      nav_block="${nav_block}</div>"

      # Combine the head insertion block with the navigation block and the JavaScript tag.
      local rep="${gap}${nav_block}${SCRIPT}"
      # Use sed to search for the pattern </head> followed by any whitespace and <body>
      # and replace it with our custom navigation block.
      sed -i -e ":a;N;\$!ba;s|</head>[ \t\r\n]*\(<body[^>]*>\)|${between}\1${rep}|" "$curr"

      # Set the previous file to the current one for navigation purposes.
      prev="$curr"
    fi

    # Update current file to the stripped file name (without anchor).
    curr="$strip_anchor"
  done

  # Process the final file in the list.
  if [ -n "$curr" ]; then
    echo "Previous: $prev   Current: $curr"
    local mapping_line=$(printf "%b" "$TITLE_MAP" | grep "^$curr#*.*@")
    echo "mapping line: $mapping_line"

    local current_title=$(echo "$mapping_line" | head -n 1 | cut -d '@' -f 2)
    [ -z "$current_title" ] && current_title="$curr"
    echo "Current Title: $current_title"

    local breadcrumbs=$(generate_breadcrumbs "$current_title")

    local nav_block="<div class=\"navigation\">"
    nav_block="${nav_block}<div class=\"breadcrumbs\">$breadcrumbs</div>"
    nav_block="${nav_block}<div class=\"page-turning\">"
    [ -n "$prev" ] && nav_block="${nav_block}<span><a href=\"$prev\">Previous</a></span>"
    nav_block="${nav_block}<span><a href=\"$TOC_FILE\">Contents</a></span>"
    nav_block="${nav_block}<span class=\"isDisabled\"><a href=\"#\" aria-disabled=\"true\">Next</a></span>"
    nav_block="${nav_block}</div>$DARK_TOGGLE"
    nav_block="${nav_block}</div>"

    local rep="${gap}${nav_block}${SCRIPT}"
    sed -i -e ":a;N;\$!ba;s|</head>[ \t\r\n]*\(<body[^>]*>\)|${between}\1${rep}|" "$curr"
  fi
}

cover_and_toc_handle () {
    # Add TOC file to TOC list
  local title="Table of Contents"
  TOC_CONTENT="<li><a href='$TOC_FILE'>$title</a></li>${TOC_CONTENT}"

  # Ensure the TOC file is included in the list so it gets a navigation block.
  TITLE_MAP="${TOC_FILE}@$title\n${TITLE_MAP}"
  FILE_LIST="${TOC_FILE} ${FILE_LIST}"

  # If a cover page exists, add it to the beginning of the file list.
  COVER_PAGE=$(detect_cover_page)
  if [ -n "$COVER_PAGE" ]; then
    TITLE_MAP="${COVER_PAGE}@Cover\n${TITLE_MAP}"
    TOC_CONTENT="<li><a href='$COVER_PAGE'>Cover</a></li>${TOC_CONTENT}"
    FILE_LIST="${COVER_PAGE} ${FILE_LIST}"
  fi

  TITLE_MAP=$(printf "%b" "$TITLE_MAP")

  # Create the TOC HTML file
  create_toc_file "$CSS_FILE" "$TOC_CONTENT"
  echo "TOC generated at: $TOC_FILE"

}

#####################################
# Main Execution Flow
#####################################

# Log the script start.
log_debug "Generate TOC Script Started"

# Detect any existing CSS file (if one exists).
CSS_FILE=$(detect_css_file)
log_debug "Existing CSS file found: $CSS_FILE"

echo ""

# Show paths to Uni-CSS and JavaScript files.
echo "The Uni-styles file is located: $STYLES_FILE"
echo "The injected JavaScript file is located: $JS_FILE"

echo ""

# TOC Source Detection
TOC_SOURCE=$(detect_toc_source)

if [ -z "$TOC_SOURCE" ]; then
  # Path 1: No TOC source file found → Generate TOC by scanning HTML files.
  log_debug "No TOC source file found. Forcing TOC creation from HTML files."
  generate_toc_from_html_files
  log_debug "Created list of HTML files: $TITLE_MAP"

  cover_and_toc_handle
  log_debug "Final list of HTML files: $TITLE_MAP"
else
  # Path 2: TOC source file found → Extract data from it.
  log_debug "Detected TOC source: $TOC_SOURCE"

  # Extract TOC lines from the navigation file.
  TITLE_MAP=$(timer extract_toc_content "$TOC_SOURCE") && log_debug "Total Elapsed Time(extract_toc_content): ${elapsed}s"
  echo "$TITLE_MAP" > nav
  log_debug "Extracted MAP:"
  echo "$TITLE_MAP"

  # Build the mapping and the TOC HTML content.
  timer generate_mapping_and_toc "$TITLE_MAP" && log_debug "Total Elapsed Time(generate_toc): ${elapsed}s"
  echo "$TOC_CONTENT" > ul
  log_debug "TOC content:"
  log_debug "$TOC_CONTENT"


  [ "$TOC_SOURCE" = "toc.ncx" ] && cover_and_toc_handle
  log_debug "Final MAP:"
  log_debug "$TITLE_MAP"
fi

log_debug "FILE_LIST:"
log_debug "$FILE_LIST"
log_debug "---"

# Add navigation blocks to HTML files.
[ -n "$FILE_LIST" ] && timer add_navigation $FILE_LIST && log_debug "Elapsed Time (add_navigation): ${elapsed}s"
echo "Navigation added to HTML files."

# Calculate and log the total elapsed execution time.
main_timer_stop=$(awk '{print $1}' /proc/uptime)
all_time=$(echo "$main_timer_stop - $main_timer_start" | bc)
log_debug "Total Elapsed Time: ${all_time}s"
