#!/usr/bin/env bash

usage() {
    echo "Usage: $0 [--config | -c CONFIG_FILE] [--font | -f FONT_FILE] [--output | -o OUTPUT_PATH]"
    echo
    echo "Options:"
    echo "  --config, -c   Path to the config.toml file."
    echo "  --font, -f     Path to the font file."
    echo "  --output, -o   Output path for the generated subset.css file (default: current directory)"
    echo "  --help, -h     Show this help message and exit"
}

# Default output is current directory.
output_path="."

# Parse command line options
while [ "$#" -gt 0 ]; do
    case "$1" in
        --config|-c)
            config_file="$2"
            shift 2
            ;;
        --font|-f)
            font_file="$2"
            shift 2
            ;;
        --output|-o)
            output_path="$2"
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check if -c and -f options are provided
if [ -z "$config_file" ]; then
    echo "Error: --config|-c option is required."
    usage
    exit 1
fi

if [ -z "$font_file" ]; then
    echo "Error: --font|-f option is required."
    usage
    exit 1
fi

# Check if config and font files exist.
if [ ! -f "$config_file" ]; then
    echo "Error: Config file '$config_file' not found."
    exit 1
fi

if [ ! -f "$font_file" ]; then
    echo "Error: Font file '$font_file' not found."
    exit 1
fi

# Extract the title and menu names from the config file.
title=$(awk -F' = ' '/^title/{print $2}' "$config_file" | tr -d '"')
menu_names=$(awk -F' = ' '/^menu/{f=1;next} /socials/{f=0} f && /name/{print $2}' "$config_file" | cut -d',' -f1 | tr -d '"' )
language_names=$(awk -F' = ' '/^language_name\./{print $2}' "$config_file" | tr -d '"' )

# If the site is multilingual, get the menu translations.
if [ -n "$language_names" ]; then
    for menu_name in $menu_names; do
        # Find the line with the menu name inside a [languages.*.translations] section and get the translated menus.
        menu_translation=$(awk -F' = ' "/\\[languages.*\\.translations\\]/{f=1;next} /^\\[/ {f=0} f && /$menu_name =/{print \$2}" "$config_file" | tr -d '"' )
        # Add the found menu value to the translations string
        menu_names+="$menu_translation"
    done
fi

# Combine the extracted strings.
combined="$title$menu_names$language_names"

# Get unique characters.
unique_chars=$(echo "$combined" | grep -o . | sort -u | tr -d '\n')

# Create a temporary file for subset.woff2.
temp_subset=$(mktemp)

# Create the subset.
pyftsubset "$font_file" \
    --text="$unique_chars" \
    --layout-features="*" --flavor="woff2" --output-file="$temp_subset" --with-zopfli

# Remove trailing slash from output path, if present.
output_path=${output_path%/}

# Base64 encode the temporary subset.woff2 file and create the CSS file.
base64_encoded_font=$(base64 -i "$temp_subset")
echo "@font-face{font-family:\"Inter Subset\";src:url(data:application/font-woff2;base64,$base64_encoded_font);}" > "$output_path/custom_subset.css"

# Remove the temporary subset.woff2 file.
rm "$temp_subset"
