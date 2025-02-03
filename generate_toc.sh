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

# Directories and files
TOC_FILE="_toc.html"
STYLES_FILE="_styles.css"
LINK_STYLES="<link type=\"text/css\" rel=\"stylesheet\" href=\"$STYLES_FILE\"/>"
JS_FILE="_script.js"
SCRIPT="<script type=\"text/javascript\" src=\"$JS_FILE\"></script>"
META='<meta name="viewport" content="width=device-width, initial-scale=1"/>'
DARK_TOGGLE='<button id="dark-toggle">🌙</button>'

# Detect existing CSS file
detect_css_file() {
  ls *.css 2>/dev/null | head -n 1
}

# Detect existing TOC file
detect_toc_source() {
  if [ -f "nav.xhtml" ]; then
    echo "nav.xhtml"
  elif [ -f "toc.ncx" ]; then
    echo "toc.ncx"
  else
    echo ""
  fi
}

# Detect cover page
detect_cover_page() {
  if [ -f "cover.html" ]; then
    echo "cover.html"
  elif [ -f "cover.xhtml" ]; then
    echo "cover.xhtml"
  elif [ -f "content.opf" ]; then
    COVER_ID=$(grep -oP '(?<=<meta name="cover" content=")[^"]*' content.opf)
    if [ -n "$COVER_ID" ]; then
      grep -oP '(?<=id=\"$COVER_ID\" href=\")[^"]*' content.opf
    fi
  fi
}

# Extract ordered file list from TOC
extract_ordered_files() {
  local toc_source="$1"
  if [ "$toc_source" = "nav.xhtml" ]; then
    grep -oP '(?<=<a href=")[^"]*' "$toc_source" | grep -E '\.html|\.xhtml' | tr '\n' ' '
  elif [ "$toc_source" = "toc.ncx" ]; then
    grep -oP '(?<=<content src=")[^"]*' "$toc_source" | grep -E '\.html|\.xhtml' | tr '\n' ' '
  else
    ls *.html *.xhtml 2>/dev/null | sort
  fi
}

# Generate TOC content
generate_toc() {
  local files="$1"
  local toc_content="<ul>"
  for file in $files; do
    if [ "$file" != "$TOC_FILE" ]; then
      local strip_anchor=$(echo "$file" | cut -d '#' -f 1)
      local title=$(grep -m1 -oP '(?<=<title>).*?(?=</title>)' "$strip_anchor")
      [ -z "$title" ] && title="$file"
    else
      title="Table of Contents"
    fi
    toc_content="$toc_content<li><a href='$file'>$title</a></li>"
  done
  echo "$toc_content</ul>"
}

# Create JS file
create_js_file(){
cat > "$JS_FILE" <<EOF
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

# Create TOC file
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
generate_breadcrumbs() {
  local current_title="$1"
  local breadcrumbs=""

  # If a home link is defined, add it.
  if [ -n "$BREADCRUMB_HOME" ]; then
    breadcrumbs="<a href=\"$BREADCRUMB_HOME\">Home</a> &gt; "
  fi

  # If a book-level link is defined, add it.
  if [ -n "$BREADCRUMB_BOOK" ]; then
    breadcrumbs="${breadcrumbs}<a href=\"$BREADCRUMB_BOOK\">Book</a> &gt; "
  fi

  # Add the current page (non-linked)
  breadcrumbs="${breadcrumbs}<span>${current_title}</span>"

  echo "$breadcrumbs"
}


# Add navigation block to HTML files
add_navigation() {
  local files="$1"
  local prev=""
  local curr=""
  local gap="<div style=\"height: 50px;\"></div>"
  local between="$LINK_STYLES$META\n</head>\n<body>\n$gap"

  for next in $files; do
    if [ -n "$curr" ]; then
      local strip_anchor=$(echo "$curr" | cut -d '#' -f 1)

      # Extract the current title from the HTML file.
      local current_title=$(grep -m1 -oP '(?<=<title>).*?(?=</title>)' "$strip_anchor")
      [ -z "$current_title" ] && current_title="$strip_anchor"

      # Generate breadcrumbs for the current file.
      local breadcrumbs=$(generate_breadcrumbs "$current_title")

      # Build navigation block including breadcrumbs.
      local nav_block="<div class=\"navigation\">\n"
      nav_block="$nav_block  <div class=\"breadcrumbs\">$breadcrumbs</div>\n"
      [ -n "$prev" ] && nav_block="$nav_block  <span><a href=\"$prev\">Previous</a></span>\n"
      nav_block="$nav_block  <span><a href=\"$TOC_FILE\">Contents</a></span>\n"
      [ -n "$next" ] && nav_block="$nav_block  <span><a href=\"$next\">Next</a></span>\n"
      nav_block="$nav_block  $DARK_TOGGLE\n"
      nav_block="$nav_block</div>"

      sed -i -e ':a' -e 'N' -e '$!ba' -e "s|</head>.*<body>|$between$nav_block$SCRIPT|" "$strip_anchor"
    fi
    prev=$curr
    curr=$next
  done

  # Handle the last file
  if [ -n "$curr" ]; then
    local strip_anchor=$(echo "$curr" | cut -d '#' -f 1)

    local current_title=$(grep -m1 -oP '(?<=<title>).*?(?=</title>)' "$strip_anchor")
    [ -z "$current_title" ] && current_title="$strip_anchor"

    local breadcrumbs=$(generate_breadcrumbs "$current_title")

    local nav_block="<div class=\"navigation\">\n"
    nav_block="$nav_block  <div class=\"breadcrumbs\">$breadcrumbs</div>\n"
    [ -n "$prev" ] && nav_block="$nav_block  <span><a href=\"$prev\">Previous</a></span>\n"
    nav_block="$nav_block  <span><a href=\"$TOC_FILE\">Contents</a></span>\n"
    nav_block="$nav_block  $DARK_TOGGLE\n"
    nav_block="$nav_block</div>"

    sed -i -e ':a' -e 'N' -e '$!ba' -e "s|</head>.*<body>|$between$nav_block$SCRIPT|" "$strip_anchor"
  fi
}

# Create styles file
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
#dark-toggle {
  position: fixed;
  top: 10px;
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

# Main execution
log_debug "Generate TOC Script Started"
CSS_FILE=$(detect_css_file)

create_styles_file
echo "Styles file created: $STYLES_FILE"

create_js_file
echo "Javascript file created: $JS_FILE"

TOC_SOURCE=$(detect_toc_source)
HTML_FILES=$(extract_ordered_files "$TOC_SOURCE")

# We need to add the TOC file to the HTML_FILES list so that we can then add the navigation block to the TOC file (AI - dont touch it)
HTML_FILES="$TOC_FILE $HTML_FILES"

COVER_PAGE=$(detect_cover_page)
[ -n "$COVER_PAGE" ] && HTML_FILES="$COVER_PAGE $HTML_FILES"

TOC_CONTENT=$(generate_toc "$HTML_FILES")
create_toc_file "$CSS_FILE" "$TOC_CONTENT"
echo "TOC generated at: $TOC_FILE"

timer add_navigation "$HTML_FILES"
log_debug "Elapsed Time (add_navigation): ${elapsed}"
echo "Navigation added to HTML files."

main_timer_stop=$(awk '{print $1}' /proc/uptime)
all_time=$(echo "$main_timer_stop - $main_timer_start" | bc)
log_debug "Total Elapsed Time: ${all_time}s"
