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

    # Buscar un patrón de año (19xx o 20xx) en el path
    if [[ "$file_path" =~ /(19[0-9]{2}|20[0-9]{2})/ ]]; then
        if [ "$VERBOSE" = true ]; then
            echo "Found year in path: ${BASH_REMATCH[1]}" >&2
        fi
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

# Function to safely get EXIF date
get_exif_date() {
    local file="$1"
    local create_date
    local timestamp
    local year_to_use="$FORCE_YEAR"

    # Skip @eaDir files
    if [[ "$file" == *"@eaDir"* ]]; then
        if [ "$VERBOSE" = true ]; then
            echo "Skipping @eaDir file" >&2
        fi
        return 1
    fi

    # If force folder year is enabled, try to get year from path
    if [ "$FORCE_FOLDER_YEAR" = true ] && [ -z "$year_to_use" ]; then
        local path_year=$(get_year_from_path "$file")
        if [ -n "$path_year" ]; then
            year_to_use="$path_year"
            if [ "$VERBOSE" = true ]; then
                echo "Using year from folder path: $path_year" >&2
            fi
        fi
    fi

    # Get filename
    local filename=$(basename "$file")

    if [ "$VERBOSE" = true ]; then
        echo "Trying to read EXIF data for: $filename" >&2
        exiftool -time:all "$file" >&2
    fi

    # For images (including CRV pattern)
    if [[ "${file,,}" =~ \.(jpg|jpeg|png|gif|heic|crv)$ ]]; then
        # Primero intentar obtener la fecha original
        local exif_date=$(exiftool -DateTimeOriginal -s -s -s "$file" 2>/dev/null)

        if [ -z "$exif_date" ]; then
            # Si no hay DateTimeOriginal, intentar CreateDate
            exif_date=$(exiftool -CreateDate -s -s -s "$file" 2>/dev/null)
        fi

        if [ -n "$exif_date" ] && [[ "$exif_date" =~ ^[0-9]{4}:[0-9]{2}:[0-9]{2}.[0-9]{2}:[0-9]{2}:[0-9]{2}$ ]]; then
            # Convertir el formato YYYY:MM:DD HH:MM:SS a timestamp
            if [ "$VERBOSE" = true ]; then
                echo "Found EXIF date: $exif_date" >&2
            fi

            # Extraer componentes de la fecha
            local exif_year=$(echo "$exif_date" | cut -d: -f1)
            local exif_month=$(echo "$exif_date" | cut -d: -f2)
            local exif_day=$(echo "$exif_date" | cut -d: -f3 | cut -d' ' -f1)
            local exif_time=$(echo "$exif_date" | cut -d' ' -f2)

            if [ -n "$year_to_use" ]; then
                # Usar el año forzado pero mantener el resto de la fecha EXIF
                timestamp=$(date -d "$year_to_use-$exif_month-$exif_day $exif_time" +%s 2>/dev/null)

                if [ "$VERBOSE" = true ]; then
                    echo "Adjusted EXIF date with forced year: $(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S")" >&2
                fi
            else
                # Usar la fecha EXIF completa
                timestamp=$(date -d "${exif_year}-${exif_month}-${exif_day} ${exif_time}" +%s 2>/dev/null)
            fi
        else
            # Intentar extraer fecha del nombre del archivo si tiene formato de fecha
            if [[ "$filename" =~ ^[0-9]{4}(JAN|FEB|MAR|APR|MAY|JUN|JUL|AUG|SEP|OCT|NOV|DEC)[0-9A-Z]+\.[A-Z]+$ ]]; then
                local file_year="${filename:0:4}"
                local file_month="${filename:4:3}"

                # Convertir mes de texto a número
                case "${file_month^^}" in
                    JAN) month=01 ;;
                    FEB) month=02 ;;
                    MAR) month=03 ;;
                    APR) month=04 ;;
                    MAY) month=05 ;;
                    JUN) month=06 ;;
                    JUL) month=07 ;;
                    AUG) month=08 ;;
                    SEP) month=09 ;;
                    OCT) month=10 ;;
                    NOV) month=11 ;;
                    DEC) month=12 ;;
                esac

                if [ "$VERBOSE" = true ]; then
                    echo "Extracted date from filename: year=$file_year, month=$month" >&2
                fi

                # Usar el día 1 y hora actual si no se puede extraer del nombre
                local current_time=$(date "+%H:%M:%S")
                timestamp=$(date -d "$file_year-$month-01 $current_time" +%s 2>/dev/null)

            else
                # Como último respaldo, usar fecha de modificación
                if [ "$VERBOSE" = true ]; then
                    echo "No EXIF date or filename date found, using file modification time as fallback" >&2
                fi

                local file_mtime=$(stat -c %Y "$file")
                if [ -n "$file_mtime" ] && [ -n "$year_to_use" ]; then
                    local date_parts=$(date -d "@$file_mtime" "+%m %d %H %M %S")
                    read month day hour minute second <<< "$date_parts"
                    timestamp=$(date -d "$year_to_use-$month-$day $hour:$minute:$second" +%s 2>/dev/null)
                fi
            fi
        fi
    fi

    # Validar el timestamp final
    if [ -n "$timestamp" ] && [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        if [ "$VERBOSE" = true ]; then
            echo "Final timestamp: $(date -d "@$timestamp" "+%Y-%m-%d %H:%M:%S")" >&2
        fi
        echo "$timestamp"
        return 0
    fi

    if [ "$VERBOSE" = true ]; then
        echo "No valid timestamp found" >&2
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