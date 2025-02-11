#!/bin/sh
# Usage: ./extract_toc.sh input_file.xml
INPUT_FILE="$1"

if [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <toc.ncx | nav.xhtml>"
    exit 1
fi

if grep -q "<ncx" "$INPUT_FILE"; then
    echo "Detected toc.ncx format. Extracting TOC..."

    # Step 1: Insert a newline before each <navPoint>.
    # This uses sed’s literal newline replacement.
    #
    # The command below must have a literal newline between the backslash and <navPoint.
    # (That is, the replacement text is an actual newline followed by <navPoint>.)
    sed 's/<navPoint/\
<navPoint/g' "$INPUT_FILE" | \
    # Step 2: Process the now separated <navPoint> blocks with awk.
    awk '
    BEGIN { RS="<navPoint"; ORS="\n\n" }
    NR > 1 {
        title = ""; href = "";
        # Try to extract title from <navLabel><text>Title</text></navLabel>
        if (match($0, /<navLabel>[[:space:]]*<text>([^<]+)<\/text>/, arr)) {
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

    # For nav.xhtml, insert a newline before each <li> tag
    sed 's/<li/\
<li/g' "$INPUT_FILE" | \
    sed -n 's/.*<a href="\([^"]*\)">\([^<]*\)<\/a>.*/\2 - \1/p'
    
else
    echo "Unknown format: $INPUT_FILE"
    exit 1
fi
