#!/bin/bash
# Script to write a String in a given file


# Verification of Argument
if [ "$#" -ne 2 ]; then
    echo "Error: Two Arguments Required"
    exit 1
fi

# Assigning inputs to vairbles 
writeFile="$1"
writeStr="$2"


# Checking if directory and file exits and creating it 
if [ ! -d "$(dirname "$writeFile")" ]; then
    echo "Directory does not exist"
    mkdir -p "$(dirname "$writeFile")" || {
        echo "Error: Failed to create directory"
        exit 1
    }
    echo "Directory created succesfully"
fi

# Wrting text to file
echo "$writeStr" > "$writeFile" || {
    echo "Error: Failed to write to $writeFile"
    exit 1
}
    echo "$writeStr written to $writeFile succesfully"