#!/bin/sh

set -e

main_timer_start=$(awk '{print $1}' /proc/uptime)

# Debugging options
DEBUG="true"  # Toggle debugging
HEX="false"   # Toggle hex debugging

# Logging functions
log_debug() {
    [ "$DEBUG" = "true" ] && echo "$@"
}

error_response() {
    local message="$1"
    log_debug "Error: $message"
    exit 1
}

# Measure time for function execution
timer() {
    local start=$(awk '{print $1}' /proc/uptime)
    "$@"
    local end=$(awk '{print $1}' /proc/uptime)
    elapsed=$(echo "$end - $start" | bc)
}

# Check if the folder is provided
if [ -z "$1" ]; then
  error_response "Usage: $0 <folder>"
fi

FOLDER="$1"

# Check if the provided path is a valid directory
if [ ! -d "$FOLDER" ]; then
  error_response "'$FOLDER' is not a valid directory."
fi

# Change directory to the provided folder so relative paths work correctly.
cd "$FOLDER" || error_response "Cannot change directory to $FOLDER"

# Directories and files
TOC_FILE="_toc.html"
STYLES_FILE="_styles.css"
LINK_STYLES="<link type=\"text/css\" rel=\"stylesheet\" href=\"$STYLES_FILE\"/>"
JS_FILE="_script.js"
SCRIPT="<script type=\"text/javascript\" src=\"$JS_FILE\"></script>"
META='<meta name="viewport" content="width=device-width, initial-scale=1"/>'
DARK_TOGGLE='<button id="dark-toggle">🌙</button>'
BREADCRUMB_HOME="../../../../"
BREADCRUMB_BOOK="../"
TOC_CONTENT=""

# Global variable to store filename-title mappings.
TITLE_MAP=""

# Detect existing CSS file
detect_css_file() {
  ls *.css 2>/dev/null | head -n 1
}

# Detect existing TOC file (nav.xhtml preferred over toc.ncx)
detect_toc_source() {
  if [ -f "toc.xhtml" ]; then
    echo "toc.xhtml"
  elif [ -f "nav.xhtml" ]; then
    echo "nav.xhtml"
  elif [ -f "toc.ncx" ]; then
    echo "toc.ncx"
  else
    echo ""
  fi
}

# Detect cover page, if any
detect_cover_page() {
  if [ -f "cover.html" ]; then
    echo "cover.html"
  elif [ -f "cover.xhtml" ]; then
    echo "cover.xhtml"
  elif [ -f "content.opf" ]; then
    #COVER_ID=$(grep -oP '(?<=<meta name="cover" content=")[^"]*' content.opf)
    COVER_ID=$(awk -F'<meta name="cover" content="|"' '/<meta name="cover"/ {print $2}' content.opf)
    if [ -n "$COVER_ID" ]; then
      #grep -oP '(?<=id=\"$COVER_ID\" href=\")[^"]*' content.opf
      awk -F'id="'$COVER_ID'" href="|"' '/id="'$COVER_ID'"/ {print $2}' content.opf
    fi
  fi
}

# Extract ordered file list from TOC source if available;
# otherwise, list files alphabetically.
extract_ordered_files() {
  local toc_source="$1"
  if [ "$toc_source" = "toc.xhtml" ]; then
    awk -F'<a href="|"' '/<a href="/ {print $2}' "$toc_source" | grep -E '\.html|\.xhtml' | tr '\n' ' '
  elif [ "$toc_source" = "nav.xhtml" ]; then
    #grep -oP '(?<=<a href=")[^"]*' "$toc_source" | grep -E '\.html|\.xhtml' | tr '\n' ' '
    awk -F'<a href="|"' '/<a href="/ {print $2}' "$toc_source" | grep -E '\.html|\.xhtml' | tr '\n' ' '
  elif [ "$toc_source" = "toc.ncx" ]; then
    #grep -oP '(?<=<content src=")[^"]*' "$toc_source" | grep -E '\.html|\.xhtml' | tr '\n' ' '
    awk -F'<content src="|"' '/<content src="/ {print $2}' "$toc_source" | grep -E '\.html|\.xhtml' | tr '\n' ' '
  else
    ls *.html *.xhtml 2>/dev/null | sort
  fi
}

# Generate TOC content and store filename-title mapping in the global variable TITLE_MAP.
generate_toc() {
  local files="$1"
  local toc_content="<ul>"

  # Loop over each file to build TOC and mapping.
  for file in $files; do
    local strip_anchor
    local title

    # Check for a toc file that hasn't been created yet.
    # Otherwise, grep will return an error: _toc.html: No such file or directory.
    if [ "$file" != "$TOC_FILE" ]; then
      # Remove any anchor from the file name.
      strip_anchor=$(echo "$file" | cut -d '#' -f 1)

      # Extract title from the HTML file.
      #title=$(grep -m1 -oP '(?<=<title>).*?(?=</title>)' "$strip_anchor")
      title=$(awk -F'<title>|</title>' '/<title>/ {print $2; exit}' "$strip_anchor")
      # If no title is found, use the file name.
      [ -z "$title" ] && title="$file"

    else
      # For the TOC file itself, use a default title.
      title="Table of Contents"
      strip_anchor="$TOC_FILE"
    fi

    # Append the mapping: file<delimiter>title
    TITLE_MAP="$TITLE_MAP$file|||$title\n"

    toc_content="$toc_content<li><a href='$file'>$title</a></li>"
  done

  toc_content="$toc_content</ul>"
  echo -e "$toc_content"
  TOC_CONTENT="$toc_content"
}

# Create JS file
create_js_file() {
cat > "$JS_FILE" << EOF
var bodyEl = document.body;
var darkButton = document.getElementById("dark-toggle");

// Check stored preference
var savedTheme = localStorage.getItem("generateTOCdarkMode");

if (savedTheme === "dark") {
  bodyEl.classList.add("dark");
} else if (savedTheme === "light") {
  bodyEl.classList.add("light");
} else if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
  bodyEl.classList.add("dark"); // Apply dark mode only if no user selection
}

darkButton.addEventListener("click", function () {
  toggleDarkMode();
});

function toggleDarkMode() {
  if (bodyEl.classList.contains("dark")) {
    bodyEl.classList.remove("dark");
    bodyEl.classList.add("light");
    localStorage.setItem("generateTOCdarkMode", "light");
  } else {
    bodyEl.classList.remove("light");
    bodyEl.classList.add("dark");
    localStorage.setItem("generateTOCdarkMode", "dark");
  }
}
EOF
}


# Create TOC file using the generated TOC content.
create_toc_file() {
  local css_file="$1"
  local toc_content="$2"
  cat > "$TOC_FILE" <<EOF
<!DOCTYPE html>
<html>
<head>
  <title>Table of Contents</title>
  <link rel="stylesheet" href="$css_file"/>
</head>
<body>
  <h1>Table of Contents</h1>
  $toc_content
</body>
</html>
EOF
}

# Generate breadcrumbs HTML for the current page.
# Usage: generate_breadcrumbs "Current Page Title"
# This function uses environment variables (BREADCRUMB_HOME and BREADCRUMB_BOOK) for optional links
generate_breadcrumbs() {
  local current_title="$1"
  local breadcrumbs=""

  # Add home link if defined.
  if [ -n "$BREADCRUMB_HOME" ]; then
    breadcrumbs="<a href=\"$BREADCRUMB_HOME\">Home</a> \> "
  fi

  # Add book-level link if defined.
  if [ -n "$BREADCRUMB_BOOK" ]; then
    breadcrumbs="${breadcrumbs}<a href=\"$BREADCRUMB_BOOK\">Book</a> \> "
  fi

  # Add the current page (non-linked)
  breadcrumbs="${breadcrumbs}<span>${current_title}</span>"

  echo "$breadcrumbs"
}

# Helper function to look up a title from the mapping file.
# This avoids re-extracting the title from the HTML file.
lookup_title() {
  local file="$1"
  # Search for the line that begins with the file name and extract the title part.
  grep "^$file|||"
  # Format: file|||title. We cut on the delimiter.
}

# Add navigation block to HTML files, now using the stored titles from TITLE_MAP variable.
add_navigation() {
  local files="$1"
  local prev=""
  local curr=""
  local gap="<div style=\"height: 50px;\"></div>"
  # Prepare the content to be inserted between </head> and <body>.
  local between="$LINK_STYLES$META\n</head>\n<body>\n$gap"

  local rep_good="<-----------------:  </head>.*<body> Found and replaced!"
  local rep_bad="</head>.*<body> NOT REPLACED!!!   :--------------------->"


  for next in $files; do
    # Remove any anchor from the file name.
    local strip_anchor
    strip_anchor=$(echo "$next" | cut -d '#' -f 1)

    # Ignore "page#anchor" right after "page" as
    # this pair will block page turning when clicking "Next".
    if [ -n "$curr" ] && [ "$strip_anchor" != $curr ]; then
      # Look up the title from the mapping file.
      local mapping_line
      mapping_line=$(echo -e "$TITLE_MAP" | grep "^$curr|||")

      # Extract title using '|||' as delimiter.
      local current_title
      current_title=$(echo "$mapping_line" | cut -d '|' -f 4)
      [ -z "$current_title" ] && current_title="$curr"
      echo "Current Title: $current_title"

      # Generate breadcrumbs for the current file.
      local breadcrumbs
      breadcrumbs=$(generate_breadcrumbs "$current_title")

      # Build navigation block HTML including breadcrumbs and navigation links.
      local nav_block
      nav_block="<div class=\"navigation\">\n"
      nav_block="$nav_block  <div class=\"breadcrumbs\">$breadcrumbs</div>\n"
      [ -n "$prev" ] && nav_block="$nav_block  <span>\< <a href=\"$prev\">Previous</a></span>\n"
      nav_block="$nav_block  <span><a href=\"$TOC_FILE\">Contents</a></span>\n"
      [ -n "$next" ] && nav_block="$nav_block  <span><a href=\"$next\">Next</a> \></span>\n"
      nav_block="$nav_block  $DARK_TOGGLE\n"
      nav_block="$nav_block</div>"

      local rep
      rep="${between}${nav_block}${SCRIPT}"
      sed -i ":a;N;\$!ba;s#</head>[ \t\r\n]*<body>#${rep}#" "$curr" && echo "$rep_good" || echo "$rep_bad"

      # move it inside the for loop to avoid blocking "Previous"
      # (when "page#anchor" right after "page" occurs) when turning pages
      prev="$curr"
    fi

    curr="$strip_anchor"
  done

  # Handle the last file in the list.
  if [ -n "$curr" ]; then
    local mapping_line
    mapping_line=$(echo -e "$TITLE_MAP" | grep "^$curr|||")
    local current_title
    current_title=$(echo "$mapping_line" | cut -d '|' -f 4)
    [ -z "$current_title" ] && current_title="$curr"
    echo "Current Title: $current_title"

    local breadcrumbs
    breadcrumbs=$(generate_breadcrumbs "$current_title")

    local nav_block
    nav_block="<div class=\"navigation\">\n"
    nav_block="$nav_block  <div class=\"breadcrumbs\">$breadcrumbs</div>\n"
    [ -n "$prev" ] && nav_block="$nav_block  <span>\< <a href=\"$prev\">Previous</a></span>\n"
    nav_block="$nav_block  <span><a href=\"$TOC_FILE\">Contents</a></span>\n"
    nav_block="$nav_block  $DARK_TOGGLE\n"
    nav_block="$nav_block</div>"

    local rep
    rep="${between}${nav_block}${SCRIPT}"
    sed -i ":a;N;\$!ba;s#</head>[ \t\r\n]*<body>#${rep}#" "$curr" && echo "$rep_good" || echo "$rep_bad"
  fi
}

# Create styles file.
create_styles_file() {
  cat > "$STYLES_FILE" <<EOF
@charset "UTF-8";
body {
  background-color: #ffffff;
  color: #000000;
  line-height: 1.6;
  font-family: "Times New Roman", Times, serif;
}
body > :not(.navigation) {
  margin: 10px;
}
ul {
  list-style-type: none;
  padding: 0;
}
a[href] {
  text-decoration: underline;
}
a[href]:hover {
  text-decoration: none;
}
.navigation {
  position: fixed;
  top: 0;
  width: 100%;
  padding: 10px;
  text-align: center;
  border-bottom: 1px solid #cccccc4d;
  background: inherit
}
.breadcrumbs {
  white-space: nowrap;
}
#dark-toggle {
  position: fixed;
  right: 10px;
  padding: 5px 10px;
  background-color: #444;
  color: white;
  border: none;
  cursor: pointer;
  border-radius: 5px;
}
.dark {
  background-color: #000000;
  color: #ffffff;
}

/* Remove automatic dark mode */
@media (prefers-color-scheme: dark) {
  /* Apply dark mode *only* if no user preference is stored */
  body:not(.light):not(.dark) {
    background-color: #000000;
    color: #ffffff;
  }
}
EOF
}

# Main execution flow
log_debug "Generate TOC Script Started"
CSS_FILE=$(detect_css_file)

create_styles_file
echo "Styles file created: $STYLES_FILE"

create_js_file
echo "Javascript file created: $JS_FILE"

TOC_SOURCE=$(detect_toc_source)
HTML_FILES=$(extract_ordered_files "$TOC_SOURCE")

# Add the TOC file to the list so that it also gets the navigation block.
HTML_FILES="$TOC_FILE $HTML_FILES"

# Detect and add cover page if it exists.
COVER_PAGE=$(detect_cover_page)
[ -n "$COVER_PAGE" ] && HTML_FILES="$COVER_PAGE $HTML_FILES"

# Generate the TOC content and build the title mapping.
generate_toc "$HTML_FILES"
create_toc_file "$CSS_FILE" "$TOC_CONTENT"
echo "TOC generated at: $TOC_FILE"

# Add navigation blocks to all HTML files.
timer add_navigation "$HTML_FILES"
log_debug "Elapsed Time (add_navigation): ${elapsed}"
echo "Navigation added to HTML files."

main_timer_stop=$(awk '{print $1}' /proc/uptime)
all_time=$(echo "$main_timer_stop - $main_timer_start" | bc)
log_debug "Total Elapsed Time: ${all_time}s"
