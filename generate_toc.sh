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

# Define filenames and HTML fragments used later in the script.
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
# CSS and JS Files Creation
#####################################

# Create the JavaScript file that handles dark mode toggling.
create_js_file() {
cat > "$JS_FILE" << 'EOF'
/* Get references to the document body and the dark mode toggle button */
var bodyEl = document.body;
var darkButton = document.getElementById("dark-toggle");

// Retrieve stored theme preference from local storage.
var savedTheme = localStorage.getItem("generateTOCdarkMode");

if (savedTheme === "dark") {
  bodyEl.classList.add("dark");
} else if (savedTheme === "light") {
  bodyEl.classList.add("light");
} else if (window.matchMedia("(prefers-color-scheme: dark)").matches) {
  // If no preference is stored and the system prefers dark mode, enable dark mode.
  bodyEl.classList.add("dark");
}

// Add a click event listener to the toggle button to switch themes.
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

function debounce(wait, func, immediate) {
  var timeout;
  return function () {
    var context = this,
      args = arguments;
    var later = function () {
      timeout = null;
      if (!immediate) {
        func.apply(context, args);
      }
    };
    var callNow = immediate && !timeout;
    clearTimeout(timeout);
    timeout = setTimeout(later, wait || 200);
    if (callNow) {
      func.apply(context, args);
    }
  };
}

// Ensure requestAnimationFrame works in old browsers
window.requestAnimationFrame =
  window.requestAnimationFrame ||
  window.webkitRequestAnimationFrame ||
  window.mozRequestAnimationFrame ||
  window.oRequestAnimationFrame ||
  window.msRequestAnimationFrame ||
  function (callback) {
    return setTimeout(callback, 16); // 60 FPS fallback
  };

var lastScrollTop = 0;
var nav = document.querySelector('.navigation');

function scroll() {
  var scrollTop =
    document.documentElement.scrollTop || document.body.scrollTop || 0;

  if (scrollTop > lastScrollTop) {
    // Scrolling down, hide navbar
    if (nav.classList) {
      nav.classList.add('hidden');
    } else {
      nav.className += ' hidden'; // Old browser fallback
    }
  } else {
    // Scrolling up, show navbar
    if (nav.classList) {
      nav.classList.remove('hidden');
    } else {
      nav.className = nav.className.replace(/(?:^|\s)hidden(?!\S)/g, '');
    }
  }

  lastScrollTop = scrollTop;
}

// Use requestAnimationFrame for smooth performance
function optimizedScroll() {
  requestAnimationFrame(scroll);
}

// Attach debounced scroll event listener
if (window.addEventListener) {
  window.addEventListener('scroll', debounce(100, optimizedScroll, false), false);
} else if (window.attachEvent) {
  window.attachEvent('onscroll', debounce(100, optimizedScroll, false)); // IE8 fallback
}
EOF
}

# Create the CSS file with styling for the TOC, navigation and pages.
create_styles_file() {
  cat > "$STYLES_FILE" <<EOF
@charset "UTF-8";
:root {
  --uni-color: #000000;
  --uni-background: #ffffff;
  --uni-scrollbar: #555555;
  --uni-scrollbarHover: #777777;
  --uni-link: #0000ee;
  --uni-link-visited: #551a8b;
  --uni-link-active: #ff0000;
  --uni-border: #7777774d;
  --uni-button-color: #c40022;
  --uni-button-background: #444444;
  --uni-image-filter: invert(0);
  --uni-header-color: initial;

  --learning-ebpf--liz-rice-2023-code-n: #000088;
  --learning-ebpf--liz-rice-2023-sidebar-background: #f7f7f7;
}
.dark {
  --uni-color: #ffffff;
  --uni-background: #000000;
  --uni-scrollbar: #aaaaaa;
  --uni-scrollbarHover: #999999;
  --uni-link: #abffb4;
  --uni-link-visited: #538a5a;
  --uni-border: #cccccc4d;
  --uni-button-color: #a4a400;
  --uni-button-background: #222222;
  --uni-image-filter: invert(1);
  --uni-header-color: #ad4200;

  --learning-ebpf--liz-rice-2023-code-n: #7373d1;
  --learning-ebpf--liz-rice-2023-sidebar-background: #000000;
}
html {
  width: 100%;
  overflow-x: hidden;
  overflow-y: scroll;
  word-break: break-word;
}
body {
  background-color: var(--uni-background);
  color: var(--uni-color);
  line-height: 1.6;
  font-family: "Times New Roman", Times, serif;
}
body > :not(.navigation) {
  margin: 10px;
}
h1, h2, h3, h4, h5, h6 {
  color: var(--uni-header-color) !important;
}
ul {
  list-style-type: none;
  padding: 0;
}
a:not([href]) {
  color: inherit;
}
a.link,
a {
  color: var(--uni-link);
}
a.link:visited,
a:visited {
  color: var(--uni-link-visited);
}
a.link:active,
a:active {
  color: var(--uni-link-active);
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
  left: 0;
  width: 100%;
  text-align: center;
  border-bottom: 1px solid var(--uni-border);
  background-color: var(--uni-background);
  transition: top 0.3s ease-in-out;
  z-index: 1;
}
.hidden {
  top: -80px;
}
/* Fallback for old browsers (if transition is unsupported) */
@media screen and (-ms-high-contrast: active), (-ms-high-contrast: none) {
  .hidden {
    display: none;
  }
}
.page-turning {
  display: inline-block;
}
.page-turning > span:first-child:before {
  content: "< ";
}
.page-turning > span:last-child:after {
  content: " >";
}
.page-turning > span {
  padding: 0 2px;
}
.breadcrumbs {
  white-space: nowrap;
  padding: 8px 0 0 8px;
}
.breadcrumbs > span:not(:last-child):after {
  content: " > ";
}
.isDisabled {
  opacity: 0.3;
}
a[aria-disabled="true"] {
  color: var(--uni-color);
  display: inline-block;  /* For IE11/ MS Edge bug */
  pointer-events: none;
  text-decoration: line-through;
}
#dark-toggle {
  padding: 5px 10px;
  background-color: var(--uni-button-background);
  color: var(--uni-button-color);
  border: none;
  cursor: pointer;
  border-radius: 5px;
  float: right;
  margin: -3px 6px 6px;
}
img {
  filter: var(--uni-image-filter);
	opacity: 0.9;
}
::-webkit-scrollbar {
  width: 10px;
  height: 10px;
}
::-webkit-scrollbar-thumb {
  background-color: var(--uni-scrollbar);
  border-radius: 5px;
}
::-webkit-scrollbar-corner {
  background-color: transparent;
}
::-webkit-scrollbar-thumb:hover {
  background-color: var(--uni-scrollbarHover);
}

/* Remove automatic dark mode */
@media (prefers-color-scheme: dark) {
  /* Apply dark mode only if no user preference is stored */
  body:not(.light):not(.dark) {
    background-color: #000000;
    color: #ffffff;
  }
}
/*-------------*/
.w {
  font-family: inherit;
}
pre code.n {
    color: var(--learning-ebpf--liz-rice-2023-code-n);
}
div.sidebar {
  background-color: var(--learning-ebpf--liz-rice-2023-sidebar-background)
}
EOF
}

#####################################
# Main Execution Flow
#####################################

# Log the script start.
log_debug "Generate TOC Script Started"

# Detect any existing CSS file (if one exists).
CSS_FILE=$(detect_css_file)

# Create the CSS and JavaScript files.
create_styles_file
echo "Styles file created: $STYLES_FILE"

create_js_file
echo "Javascript file created: $JS_FILE"

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
create_toc_file "$CSS_FILE" "$TOC_CONTENT"
echo "TOC generated at: $TOC_FILE"

# Add navigation blocks to all HTML files and measure the time taken.
timer add_navigation "$HTML_FILES"
log_debug "Elapsed Time (add_navigation): ${elapsed}s"
echo "Navigation added to HTML files."

# Calculate and log the total elapsed execution time.
main_timer_stop=$(awk '{print $1}' /proc/uptime)
all_time=$(echo "$main_timer_stop - $main_timer_start" | bc)
log_debug "Total Elapsed Time: ${all_time}s"
