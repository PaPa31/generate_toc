#!/bin/sh
# Usage: ./extract_toc.sh input_file.xml
INPUT_FILE="$1"

if [ -z "$INPUT_FILE" ]; then
    echo "Usage: $0 <toc.ncx | nav.xhtml>"
    exit 1
fi

if grep -q "<ncx" "$INPUT_FILE"; then
    echo "Detected toc.ncx format. Extracting TOC..."

    # Step 1: Insert a newline before each <navPoint>
    sed 's/<navPoint/\
<navPoint/g' "$INPUT_FILE" | \
    # Step 2: Process the now separated <navPoint> blocks using AWK with index()/substr() extraction.
    awk 'BEGIN{RS="<navPoint"; ORS="\n\n"} NR>1{
      pos1=index($0,"<navLabel>"); title="";
      if(pos1>0){
        rest1=substr($0, pos1+length("<navLabel>"));
        pos2=index(rest1,"<text>");
        if(pos2>0){
          rest2=substr(rest1, pos2+length("<text>"));
          pos3=index(rest2,"</text>");
          if(pos3>0) title=substr(rest2, 1, pos3-1);
        }
      }
      posC=index($0,"<content"); href="";
      if(posC>0){
        restC=substr($0, posC);
        posS=index(restC,"src=\"");
        if(posS>0){
          restS=substr(restC, posS+length("src=\""));
          posQ=index(restS,"\"");
          if(posQ>0) href=substr(restS, 1, posQ-1);
        }
      }
      if(title!="" && href!="") print title " - " href
    }'

elif grep -q "<nav " "$INPUT_FILE"; then
    echo "Detected nav.xhtml format. Extracting TOC..."

   # If a <nav> with epub:type="toc" exists, extract that block only.
    if grep -q '<nav[^>]*epub:type="toc"' "$INPUT_FILE"; then
        # Insert newline before <nav> to help extraction (handles minified files)
        sed 's/<nav/\n<nav/g' "$INPUT_FILE" | \
        sed -n '/<nav[^>]*epub:type="toc"[^>]*>/,/<\/nav>/p' | \
        sed 's/<li/\
<li/g' | \
        sed -n 's/.*<a href="\([^"]*\)">\([^<]*\)<\/a>.*/\2 - \1/p'
    else
        # Otherwise, process the whole file.
        sed 's/<li/\
<li/g' "$INPUT_FILE" | \
        sed -n 's/.*<a href="\([^"]*\)">\([^<]*\)<\/a>.*/\2 - \1/p'
    fi

else
    echo "Unknown format: $INPUT_FILE"
    exit 1
fi
