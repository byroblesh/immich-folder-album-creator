#!/bin/bash

# Función para mostrar el uso del script
show_usage() {
    echo "Usage: $0 [-v] [-d] source_path"
    echo "  -v, --verbose  : Verbose mode - show detailed processing information"
    echo "  -d, --dry-run  : Dry run mode - show what would be done without making changes"
    echo "  source_path    : Path containing .xmp files"
    exit 1
}

# Parse arguments
VERBOSE=false
DRY_RUN=false

while getopts "vdh-:" opt; do
    case $opt in
        v) VERBOSE=true ;;
        d) DRY_RUN=true ;;
        h) show_usage ;;
        -)
            case "${OPTARG}" in
                verbose) VERBOSE=true ;;
                dry-run) DRY_RUN=true ;;
                *) show_usage ;;
            esac ;;
        ?) show_usage ;;
    esac
done

shift $((OPTIND-1))
SOURCE_PATH="$1"
PHOTOS_PATH="/app/immich/archivo"

# Validar argumentos
if [ -z "$SOURCE_PATH" ]; then
    echo "Error: source_path is required"
    show_usage
fi

if [ ! -d "$SOURCE_PATH" ]; then
    echo "Error: source_path directory does not exist: $SOURCE_PATH"
    exit 1
fi

if [ ! -d "$PHOTOS_PATH" ]; then
    echo "Error: photos directory does not exist: $PHOTOS_PATH"
    exit 1
fi

# Inicializar contadores
files_processed=0
files_would_copy=0
files_copied=0
files_not_found=0

# Mostrar modo de ejecución
if [ "$DRY_RUN" = true ]; then
    echo "Running in DRY-RUN mode - No files will be copied"
fi
echo "Processing directory: $SOURCE_PATH"
echo "Looking for originals in: $PHOTOS_PATH"

# Procesar todos los archivos .xmp
while IFS= read -r -d '' xmp_file; do
    ((files_processed++))

    if [ "$VERBOSE" = true ]; then
        echo -e "\nProcessing XMP file: $xmp_file"
    fi

    # Obtener el nombre base del archivo (sin .xmp)
    base_name=$(basename "$xmp_file" .xmp)

    if [ "$VERBOSE" = true ]; then
        echo "Looking for original file: $base_name"
    fi

    # Buscar el archivo original en el directorio de fotos
    original_file=$(find "$PHOTOS_PATH" -type f -name "$base_name" -print -quit)

    if [ -n "$original_file" ]; then
        target_dir=$(dirname "$xmp_file")
        target_file="$target_dir/$(basename "$original_file")"

        if [ "$VERBOSE" = true ]; then
            echo "Found original: $original_file"
            echo "Target location: $target_file"
        fi

        if [ "$DRY_RUN" = true ]; then
            echo -e "\nWould copy file:"
            echo "  From: $original_file"
            echo "  To:   $target_file"
            echo "  Would delete: $xmp_file"
            ((files_would_copy++))
        else
            # Copiar el archivo original
            if cp -f "$original_file" "$target_dir/"; then
                ((files_copied++))
                echo -e "\nCopied file:"
                echo "  From: $original_file"
                echo "  To:   $target_file"

                # Eliminar el archivo XMP
                if rm -f "$xmp_file"; then
                    echo "  Deleted XMP: $xmp_file"
                    if [ "$VERBOSE" = true ]; then
                        echo "Successfully copied file and removed XMP"
                    fi
                else
                    echo "  Error: Could not delete XMP file: $xmp_file"
                fi
            else
                echo "Error copying file: $original_file"
            fi
        fi
    else
        ((files_not_found++))
        echo "Original file not found for: $base_name"
    fi

done < <(find "$SOURCE_PATH" -type f -name "*.xmp" -print0)

# Mostrar resumen
echo -e "\n=== Processing Summary ==="
echo "Total XMP files processed: $files_processed"
if [ "$DRY_RUN" = true ]; then
    echo "Files that would be copied: $files_would_copy"
    echo "XMP files that would be deleted: $files_would_copy"
else
    echo "Files successfully copied: $files_copied"
    echo "XMP files deleted: $files_copied"
fi
echo "Original files not found: $files_not_found"

if [ "$DRY_RUN" = true ]; then
    echo -e "\nThis was a dry run. No files were actually copied."
    echo "Run without -d or --dry-run to perform the actual copy operation."
fi