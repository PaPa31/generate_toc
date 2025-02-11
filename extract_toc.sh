#!/bin/sh

# Usage: ./extract_toc.sh input_file.xml
INPUT_FILE="$1"

if [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <toc.ncx | nav.xhtml>"
    exit 1
fi

if grep -q "<ncx" "$INPUT_FILE"; then
    echo "Detected toc.ncx format. Extracting TOC..."
    
    # Insert newline before each <navPoint> to force record separation even if XML is minified.
    sed 's/<navPoint/\n<navPoint/g' "$INPUT_FILE" | awk '
    NR > 1 {
        title = ""; href = "";
        # Try to extract title from <navLabel><text>Title</text></navLabel>
        if (match($0, /<navLabel>[ \t\r\n]*<text>([^<]+)<\/text>/, arr)) {
            title = arr[1];
        } else if (match($0, /<text>([^<]+)<\/text>/, arr)) {
            title = arr[1];
        }
        # Extract href from <content ... src="...">
        if (match($0, /<content[^>]+src="([^">]+)"/, arr)) {
            href = arr[1];
        }
        if (title != "" && href != "") {
            print title " - " href;
        }
    }'

elif grep -q "<nav " "$INPUT_FILE"; then
    echo "Detected nav.xhtml format. Extracting TOC..."
    
    # Insert newline before each <li> element if needed
    sed 's/<li/\n<li/g' "$INPUT_FILE" | sed -n 's/.*<a href="\([^"]*\)">\([^<]*\)<\/a>.*/\2 - \1/p'
    
else
    echo "Unknown format: $INPUT_FILE"
    exit 1
fi
