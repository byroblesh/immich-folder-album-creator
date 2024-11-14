#!/bin/bash

# Function to show usage instructions
show_usage() {
    echo "Usage: $0 [-u] [-d limit] [-v] folder_path"
    echo "  -u          : Update dates (without this flag, only shows preview)"
    echo "  -d limit    : Debug limit - show only first 'limit' number of changes"
    echo "  -v          : Verbose mode - show detailed processing information"
    echo "  folder_path : Path to the folder containing media files"
    exit 1
}

# Check if exiftool is installed
if ! command -v exiftool &> /dev/null; then
    echo "Error: exiftool is required but not installed."
    echo "Install it with: sudo apt-get install libimage-exiftool-perl"
    exit 1
fi

# Function to safely get EXIF date
get_exif_date() {
    local file="$1"
    local create_date
    local timestamp

    # Check if it's a video file (case insensitive)
    if [[ "${file,,}" =~ \.(mp4|mov|avi|mkv|m4v|mpg|mpeg|mts|m2ts|wmv)$ ]]; then
        # Get Create Date
        create_date=$(exiftool -CreateDate -s3 "$file" 2>/dev/null)

        # Check if it's a UTC date (Instagram format)
        if [[ "$create_date" =~ [0-9]{4}:[0-9]{2}:[0-9]{2}.[0-9]{2}:[0-9]{2}:[0-9]{2}\.000Z$ ]]; then
            # Convert date format for date command
            year=$(echo "$create_date" | cut -d: -f1)
            month=$(echo "$create_date" | cut -d: -f2)
            day=$(echo "$create_date" | cut -d: -f3 | cut -d' ' -f1)
            time=$(echo "$create_date" | cut -d' ' -f2 | cut -d. -f1)

            # Format date string
            formatted_date="${year}-${month}-${day} ${time} UTC"
            timestamp=$(date -d "$formatted_date" +%s 2>/dev/null)

            if [ -n "$timestamp" ] && [[ "$timestamp" =~ ^[0-9]+$ ]]; then
                echo "$timestamp"
                return
            fi
        else
            # Try standard video date formats
            timestamp=$(exiftool -CreateDate -MediaCreateDate -TrackCreateDate -DateTimeOriginal \
                               -d "%s" "$file" 2>/dev/null | \
                       awk '{print $4}' | grep -v '^$' | grep -v '^0$' | sort -n | head -1)
            if [ -n "$timestamp" ] && [[ "$timestamp" =~ ^[0-9]+$ ]]; then
                echo "$timestamp"
                return
            fi
        fi
    else
        # Image files
        timestamp=$(exiftool -DateTimeOriginal -CreateDate -d "%s" "$file" 2>/dev/null | \
                   awk '{print $4}' | grep -v '^$' | sort -n | head -1)
        if [ -n "$timestamp" ] && [[ "$timestamp" =~ ^[0-9]+$ ]]; then
            echo "$timestamp"
            return
        fi
    fi

    echo ""
}

# Function to safely get current file date
get_file_date() {
    local file="$1"
    local date_str
    date_str=$(stat -c %Y "$file" 2>/dev/null)
    if [ -n "$date_str" ] && [ "$date_str" -eq "$date_str" ] 2>/dev/null; then
        echo "$date_str"
    else
        echo ""
    fi
}

# Parse arguments
UPDATE_MODE=false
DEBUG_LIMIT=""
VERBOSE=false

while getopts "ud:vh" opt; do
    case $opt in
        u) UPDATE_MODE=true ;;
        d) DEBUG_LIMIT=$OPTARG ;;
        v) VERBOSE=true ;;
        h) show_usage ;;
        ?) show_usage ;;
    esac
done

shift $((OPTIND-1))
FOLDER_PATH="$1"

if [ -z "$FOLDER_PATH" ]; then
    echo "Error: Folder path is required"
    show_usage
fi

if [ ! -d "$FOLDER_PATH" ]; then
    echo "Error: Folder not found: $FOLDER_PATH"
    exit 1
fi

# Initialize counters
files_processed=0
files_updated=0
files_skipped=0

echo "Processing directory: $FOLDER_PATH"

# Process all files
while IFS= read -r -d '' file; do
    # Skip if not a media file (case insensitive)
    if [[ ! "${file,,}" =~ \.(jpg|jpeg|png|heic|heif|arw|cr2|cr3|nef|raw|mp4|mov|avi|mkv|m4v|mpg|mpeg|mts|m2ts|wmv)$ ]]; then
        continue
    fi

    ((files_processed++))
    filename=$(basename "$file")

    if [ "$VERBOSE" = true ]; then
        echo -e "\nProcessing: $file"
        if [[ "${file,,}" =~ \.(mp4|mov|avi|mkv|m4v|mpg|mpeg|mts|m2ts|wmv)$ ]]; then
            echo "Available video metadata dates:"
            exiftool -time:all "$file" | grep -i "date"

            create_date=$(exiftool -CreateDate -s3 "$file" 2>/dev/null)
            echo "Raw Create Date: $create_date"

            if [[ "$create_date" =~ \.000Z$ ]]; then
                echo "Detected UTC format date"
                year=$(echo "$create_date" | cut -d: -f1)
                month=$(echo "$create_date" | cut -d: -f2)
                day=$(echo "$create_date" | cut -d: -f3 | cut -d' ' -f1)
                time=$(echo "$create_date" | cut -d' ' -f2 | cut -d. -f1)
                formatted_date="${year}-${month}-${day} ${time} UTC"
                echo "Formatted date: $formatted_date"
                test_timestamp=$(date -d "$formatted_date" +%s 2>/dev/null)
                if [ -n "$test_timestamp" ] && [[ "$test_timestamp" =~ ^[0-9]+$ ]]; then
                    echo "Converted timestamp: $test_timestamp"
                    echo "Human readable: $(date -d "@$test_timestamp" "+%Y-%m-%d %H:%M:%S")"
                fi
            fi

            timestamp=$(get_exif_date "$file")
            if [ -n "$timestamp" ] && [[ "$timestamp" =~ ^[0-9]+$ ]]; then
                echo "Final timestamp: $timestamp"
                echo "Human readable: $(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S")"
            else
                echo "No valid timestamp found"
            fi
        fi
    fi

    # Get the EXIF date
    exif_date=$(get_exif_date "$file")

    if [ -n "$exif_date" ] && [[ "$exif_date" =~ ^[0-9]+$ ]]; then
        current_date=$(stat -c %Y "$file")
        date_difference=$((current_date - exif_date))

        if [ ${date_difference#-} -gt 1 ]; then
            if [ "$UPDATE_MODE" = true ]; then
                echo -e "\nUpdating file:"
                echo "  Path: $file"
                echo "  From: $(date -d "@$current_date" "+%Y-%m-%d %H:%M:%S")"
                echo "  To:   $(date -d "@$exif_date" "+%Y-%m-%d %H:%M:%S")"
                if touch -t $(date -d "@$exif_date" "+%Y%m%d%H%M.%S") "$file"; then
                    ((files_updated++))
                else
                    echo "  Error: Failed to update file date"
                fi
            else
                echo -e "\nWould update file:"
                echo "  Path: $file"
                echo "  Current: $(date -d "@$current_date" "+%Y-%m-%d %H:%M:%S")"
                echo "  New:     $(date -d "@$exif_date" "+%Y-%m-%d %H:%M:%S")"
            fi
        else
            ((files_skipped++))
            if [ "$VERBOSE" = true ]; then
                echo "Skipped: dates match or difference is negligible"
            fi
        fi
    else
        ((files_skipped++))
        if [ "$VERBOSE" = true ]; then
            echo "Skipped: no valid date found"
        fi
    fi

    # Check if we've hit the debug limit
    if [ -n "$DEBUG_LIMIT" ] && [ $files_processed -ge "$DEBUG_LIMIT" ]; then
        echo "Reached debug limit of $DEBUG_LIMIT files"
        break
    fi
done < <(find "$FOLDER_PATH" -type f -print0)

# Show summary
echo -e "\n=== Processing Summary ==="
echo "Total files processed: $files_processed"
echo "Files updated: $files_updated"
echo "Files skipped: $files_skipped"

if [ "$UPDATE_MODE" = false ]; then
    echo -e "\nThis was a preview. Run with -u to apply changes."
fi