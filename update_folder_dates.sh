#!/bin/bash

# Function to show usage instructions
show_usage() {
    echo "Usage: $0 [-u] [-d limit] [-v] [-y year] [-f] folder_path"
    echo "  -u          : Update dates (without this flag, only shows preview)"
    echo "  -d limit    : Debug limit - show only first 'limit' number of changes"
    echo "  -v          : Verbose mode - show detailed processing information"
    echo "  -y year     : Force specific year for dates (e.g., -y 1990)"
    echo "  -f          : Force year from folder path if found (e.g., path/1992/file.jpg uses 1992)"
    echo "  folder_path : Path to the folder containing media files"
    exit 1
}

# Parse arguments
UPDATE_MODE=false
DEBUG_LIMIT=""
VERBOSE=false
FORCE_YEAR=""
FORCE_FOLDER_YEAR=false

while getopts "ud:vy:fh" opt; do
    case $opt in
        u) UPDATE_MODE=true ;;
        d) DEBUG_LIMIT=$OPTARG ;;
        v) VERBOSE=true ;;
        y) FORCE_YEAR=$OPTARG ;;
        f) FORCE_FOLDER_YEAR=true ;;
        h) show_usage ;;
        ?) show_usage ;;
    esac
done

shift $((OPTIND-1))
FOLDER_PATH="$1"

# Validate year
if [ -n "$FORCE_YEAR" ]; then
    if ! [[ "$FORCE_YEAR" =~ ^[0-9]{4}$ ]]; then
        echo "Error: Year must be a 4-digit number"
        exit 1
    fi
fi

# Function to extract year from path
get_year_from_path() {
    local file_path="$1"
    local year_from_path

    # Buscar un patrón de año (19xx o 20xx) en el path
    if [[ "$file_path" =~ /(19[0-9]{2}|20[0-9]{2})/ ]]; then
        year_from_path="${BASH_REMATCH[1]}"
        if [ "$VERBOSE" = true ]; then
            echo "Found year in path: $year_from_path"
        fi
        echo "$year_from_path"
        return 0
    fi

    echo ""
    return 1
}

# Function to safely get EXIF date
get_exif_date() {
    local file="$1"
    local create_date
    local timestamp
    local year_to_use="$FORCE_YEAR"

    # If force folder year is enabled, try to get year from path
    if [ "$FORCE_FOLDER_YEAR" = true ]; then
        local path_year=$(get_year_from_path "$file")
        if [ -n "$path_year" ]; then
            year_to_use="$path_year"
            if [ "$VERBOSE" = true ]; then
                echo "Using year from folder path: $path_year"
            fi
        fi
    fi

    # Skip @eaDir files
    if [[ "$file" == *"@eaDir"* ]]; then
        if [ "$VERBOSE" = true ]; then
            echo "Skipping @eaDir file"
        fi
        return 1
    fi

    # Get filename
    local filename=$(basename "$file")

    # Check for Scan- pattern first
    if [[ "$filename" =~ ^Scan-([0-9]{2})([0-9]{2})([0-9]{2})-[0-9]+\.jpg$ ]]; then
        if [ "$VERBOSE" = true ]; then
            echo "Found Scan- pattern in filename"
        fi

        local yy="${BASH_REMATCH[1]}"
        local mm="${BASH_REMATCH[2]}"
        local dd="${BASH_REMATCH[3]}"

        # Try to get time from EXIF data first
        local exif_time=$(exiftool -DateTimeOriginal -CreateDate -s3 "$file" 2>/dev/null | head -1)
        local file_time

        if [ -n "$exif_time" ] && [[ "$exif_time" =~ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
            # Extract time from EXIF data
            file_time=$(echo "$exif_time" | cut -d' ' -f2)
            if [ "$VERBOSE" = true ]; then
                echo "Using time from EXIF data: $file_time"
            fi
        else
            # Fallback to file system time
            file_time=$(date -r "$file" "+%H:%M:%S")
            if [ "$VERBOSE" = true ]; then
                echo "Using time from file system: $file_time"
            fi
        fi

        # Use forced year if provided, otherwise use 19xx
        if [ -n "$year_to_use" ]; then
            year="$year_to_use"
        else
            year="19$yy"
        fi

        if [ "$VERBOSE" = true ]; then
            echo "Extracted date components: year=$year, month=$mm, day=$dd, time=$file_time"
        fi

        # Create timestamp using the extracted time
        timestamp=$(date -d "$year-$mm-$dd $file_time" +%s 2>/dev/null)

        if [ -n "$timestamp" ] && [[ "$timestamp" =~ ^[0-9]+$ ]]; then
            if [ "$VERBOSE" = true ]; then
                echo "Created timestamp from Scan- filename: $(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S")"
            fi
            echo "$timestamp"
            return 0
        fi

    elif [[ "${file,,}" =~ \.(mp4|mov|avi|mkv|m4v|mpg|mpeg|mts|m2ts|wmv)$ ]]; then
        # Get Create Date
        create_date=$(exiftool -CreateDate -s3 "$file" 2>/dev/null)

        if [[ "$create_date" =~ [0-9]{4}:[0-9]{2}:[0-9]{2}.[0-9]{2}:[0-9]{2}:[0-9]{2}\.000Z$ ]]; then
            year=$(echo "$create_date" | cut -d: -f1)
            month=$(echo "$create_date" | cut -d: -f2)
            day=$(echo "$create_date" | cut -d: -f3 | cut -d' ' -f1)
            time=$(echo "$create_date" | cut -d' ' -f2 | cut -d. -f1)

            formatted_date="${year}-${month}-${day} ${time} UTC"
            timestamp=$(date -d "$formatted_date" +%s 2>/dev/null)
        else
            timestamp=$(exiftool -CreateDate -MediaCreateDate -TrackCreateDate -DateTimeOriginal \
                               -d "%s" "$file" 2>/dev/null | \
                       awk '{print $4}' | grep -v '^$' | grep -v '^0$' | sort -n | head -1)
        fi
    else
        # Regular image files
        timestamp=$(exiftool -DateTimeOriginal -CreateDate -d "%s" "$file" 2>/dev/null | \
                   awk '{print $4}' | grep -v '^$' | sort -n | head -1)
    fi

    # Si tenemos timestamp y año forzado (para archivos que no son Scan-)
    if [ -n "$timestamp" ] && [[ "$timestamp" =~ ^[0-9]+$ ]] && [ -n "$year_to_use" ]; then
        local date_parts=$(date -d "@$timestamp" "+%m %d %H %M %S")
        read month day hour minute second <<< "$date_parts"

        if [ "$VERBOSE" = true ]; then
            echo "Adjusting year from $(date -d "@$timestamp" +%Y) to $year_to_use"
        fi

        timestamp=$(date -d "$year_to_use-$month-$day $hour:$minute:$second" +%s)
    fi

    if [ -n "$timestamp" ] && [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        echo "$timestamp"
        return 0
    fi

    echo ""
    return 1
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

# Function to adjust timestamp with forced year
adjust_year_if_needed() {
    local timestamp="$1"
    local original_year

    if [ -n "$FORCE_YEAR" ] && [ -n "$timestamp" ]; then
        original_year=$(date -d "@$timestamp" +%Y)
        if [ "$original_year" != "$FORCE_YEAR" ]; then
            if [ "$VERBOSE" = true ]; then
                echo "Adjusting year from $original_year to $FORCE_YEAR"
            fi
            # Get month, day, hour, minute, second from original date
            local date_parts=$(date -d "@$timestamp" "+%m %d %H %M %S")
            read month day hour minute second <<< "$date_parts"
            # Create new timestamp with forced year
            timestamp=$(date -d "$FORCE_YEAR-$month-$day $hour:$minute:$second" +%s)
        fi
    fi
    echo "$timestamp"
}

# Initialize counters
files_processed=0
files_updated=0
files_skipped=0

echo "Processing directory: $FOLDER_PATH"

# Process all files
while IFS= read -r -d '' file; do
    # Skip @eaDir files and directories
    if [[ "$file" == *"@eaDir"* ]]; then
        if [ "$VERBOSE" = true ]; then
            echo "Skipping @eaDir path: $file"
        fi
        continue
    fi

    # Skip if not a media file (case insensitive)
    if [[ ! "${file,,}" =~ \.(jpg|jpeg|png|heic|heif|arw|cr2|cr3|nef|raw|mp4|mov|avi|mkv|m4v|mpg|mpeg|mts|m2ts|wmv)$ ]]; then
        continue
    fi

    ((files_processed++))
    filename=$(basename "$file")

    if [ "$VERBOSE" = true ]; then
        echo -e "\nProcessing: $file"
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
done < <(find "$FOLDER_PATH" -type f -not -path "*/@eaDir/*" -print0)

# Show summary
echo -e "\n=== Processing Summary ==="
echo "Total files processed: $files_processed"
echo "Files updated: $files_updated"
echo "Files skipped: $files_skipped"

if [ "$UPDATE_MODE" = false ]; then
    echo -e "\nThis was a preview. Run with -u to apply changes."
fi