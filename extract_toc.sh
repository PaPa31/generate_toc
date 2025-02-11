#!/bin/sh

# Usage: ./extract_toc.sh input_file.xml
INPUT_FILE="$1"

if [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <toc.ncx | nav.xhtml>"
    exit 1
fi

if grep -q "<ncx" "$INPUT_FILE"; then
    echo "Detected toc.ncx format. Extracting TOC..."
    
    # Extract navPoints and format output as "title - href"
    awk '
    BEGIN { RS="<navPoint"; ORS="\n\n" }
    NR > 1 {
        title = ""; href = "";
        if (match($0, /<text>([^<]+)<\/text>/, arr)) title = arr[1];
        if (match($0, /src="([^"]+)"/, arr)) href = arr[1];
        if (title && href) print title " - " href;
    }
    ' "$INPUT_FILE"

elif grep -q "<nav " "$INPUT_FILE"; then
    echo "Detected nav.xhtml format. Extracting TOC..."
    
    # Extract <li> links and format output as "title - href"
    sed -n 's/.*<a href="\([^"]*\)">\([^<]*\)<\/a>.*/\2 - \1/p' "$INPUT_FILE"

else
    echo "Unknown format: $INPUT_FILE"
    exit 1
fi
