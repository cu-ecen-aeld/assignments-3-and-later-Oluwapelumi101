#!/bin/sh

# Error check for arguements 
if [ "$#" -ne 2 ]; then
    echo "Error: Two Arguments Required"
    exit 1
fi

# Declaring variables
filesDir="$1"
searchStr="$2"

if [ ! -d "$filesDir" ]; then
    echo "Error: $filesDir is not a directory"
    exit 1
fi

# Results
X=$(find -L "$filesDir" -type f  | wc -l )
Y=$(grep -r -I -F -- "$searchStr" "$filesDir" | wc -l )

echo "The number of files are $X and the number of matching lines are $Y"

