#!/usr/bin/env bash

#################################################################################
# This script is run by git before a commit is made.                            #
# To use it, copy it to .githooks/pre-commit and make it executable.            #
# Alternatively, run the following command from the root of the repo:           #
# git config core.hooksPath .githooks                                           #
#                                                                               #
#                                  FEATURES                                     #
# Updates the "updated" field in the front matter of .md files.                 #
# Compresses PNG files with either oxipng or optipng if available.              #
# Runs subset-font.sh if config.toml has been modified.                         #
#                                                                               #
# Stops you from commiting:                                                     #
# - a draft .md file                                                            #
# - a file with a "TODO"                                                        #
# - a JS file without a minified version                                        #
# - a minified JS file that isn't as small as it can be                         #
# - a config.toml and theme.toml with different amounts of lines in [extra]     #
#################################################################################


# find this scripts location.
SOURCE=${BASH_SOURCE[0]}
while [ -L "${SOURCE}" ]; do # resolve "${SOURCE}" until the file is no longer a symlink.
  DIR=$( cd -P "$( dirname "${SOURCE}" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "${SOURCE}")
   # if "${SOURCE}" was a relative symlink, we need to resolve it relative to the path where the symlink file was located.
  [[ "${SOURCE}" != /* ]] && SOURCE="${DIR}/${SOURCE}"
done
DIR=$( cd -P "$( dirname "${SOURCE}" )" >/dev/null 2>&1 && pwd )

cd "${DIR}/.." || exit

ENV_ROOT=$(pwd)
export ENV_ROOT=${ENV_ROOT}

# Function to exit the script with an error message.
function error_exit() {
    echo "ERROR: $1" >&2
    exit "${2:-1}"
}

# Function to extract the date from the front matter.
function extract_date() {
    local file="$1"
    local field="$2"
    grep -m 1 "^$field =" "${file}" | sed -e "s/$field = //" -e 's/ *$//'
}

# Function to check if the .md file is a draft.
function is_draft() {
    local file="$1"
    awk '/^\+\+\+$/,/^\+\+\+$/ { if(/draft = true/) exit 0 } END { exit 1 }' "${file}"
}

# Check if the file contains "TODO".
function contains_todo() {
    local file="$1"
    grep -q "TODO" "${file}"
}

# Check for changes outside of the front matter.
function has_body_changes() {
    local file="$1"
    local in_front_matter=1
    local triple_plus_count=0

    diff_output=$(git diff --unified=999 --cached --output-indicator-new='%' --output-indicator-old='&' "${file}")

    while read -r line; do
        if [[ "$line" =~ ^\+\+\+$ ]]; then
            triple_plus_count=$((triple_plus_count + 1))
            if [[ $triple_plus_count -eq 2 ]]; then
                in_front_matter=0
            fi
        elif [[ $in_front_matter -eq 0 ]]; then
            if [[ "$line" =~ ^[\%\&] ]]; then
                return 0
            fi
        fi
    done <<< "$diff_output"
    return 1
}

# Function to update the social media card for a post or section.
function generate_and_commit_card {
    local file=$1
    local cleaned=$(dirname ${file#"content"})
    local output_path="static/images/social_cards$cleaned"

    mkdir -p "${output_path}"
 
    social_media_card=$("${ENV_ROOT}/scripts/social-cards.sh" -o "${output_path}" -b http://127.0.0.1:1111 -u -p -i "${file}") || {
        echo "Failed to update social media card for ${file}"
        exit 1
    }

    git add "$social_media_card" || {
        echo "Failed to add social media card $social_media_card"
        exit 1
    }

    git add "${file}" || {
        echo "Failed to add ${file}"
        exit 1
    }
}

export -f generate_and_commit_card

function has_minified_version() {
    local file="$1"
    local extension="${file##*.}"
    local minified_file="${file%.*}.min.$extension"
    [ -f "$minified_file" ]
}

function is_minified() {
    local file="$1"

    # Check if terser and uglifyjs are installed.
    if ! command -v terser &> /dev/null || ! command -v uglifyjs &> /dev/null; then
        echo "Either terser or uglifyjs is not installed. Skipping minification check."
        return 0
    fi

    # Original file size.
    local original_size=$(wc -c < "${file}")

    # File size after compression with terser.
    local terser_size=$(terser --compress --mangle -- "${file}" | wc -c)

    # File size after compression with uglifyjs.
    local uglifyjs_size=$(uglifyjs --compress --mangle -- "${file}" | wc -c)

    # Check if the file is already as small as or smaller than both minified versions.
    if (( original_size <= terser_size && original_size <= uglifyjs_size )); then
        return 0
    fi

    # If the file isn't as small as it can be, suggest the better compressor in the error message
    if (( terser_size < uglifyjs_size )); then
        error_exit "Minified JS file ${file} isn't as small as it can be! Try using terser for better compression."
    else
        error_exit "Minified JS file ${file} isn't as small as it can be! Try using uglifyjs for better compression."
    fi
}

# Check if the script is being run from the root of the repo.
if [[ ! $(git rev-parse --show-toplevel) == $(pwd) ]]; then
    error_exit "This script must be run from the root of the repo."
fi

# Check if oxipng is installed.
png_compressor=""
if command -v oxipng &> /dev/null; then
    png_compressor="oxipng -o max"
elif command -v optipng &> /dev/null; then
    png_compressor="optipng -o 7"
fi

##################################################################
# Compress PNG files with either oxipng or optipng if available. #
# Update the "updated" field in the front matter of .md files.   #
#          https://osc.garden/blog/zola-date-git-hook/           #
# Ensure the [extra] section from config.toml and theme.toml     #
# have the same amount of lines.                                 #
# Ensure JavaScript files are minified.                          #
##################################################################

# Get the newly added and modified files.
all_changed_files=$(git diff --cached --name-only --diff-filter=AM)

script_name=$(basename "$0")
# Loop through all newly added or modified files.
for file in $all_changed_files; do
    file_name=$(basename "${file}")

    # Ignore this script and the changelog.
    if [[ "${file}_name" == "$script_name" ]] || [[ "${file}_name" == "CHANGELOG.md" ]]; then
        continue
    fi

    # If the file is a PNG and png_compressor is set, compress it and add it to the commit.
    if [[ "${file}" == *.png ]] && [[ -n "$png_compressor" ]]; then
        $png_compressor "${file}" || error_exit "Failed to compress PNG file ${file}"
        git add --force "${file}" || error_exit "Failed to add compressed PNG file ${file}"
        continue
    fi

    # If the file contains "TODO", abort the commit.
    if contains_todo "${file}"; then
        error_exit "File ${file} contains TODO! Remove or complete the TODO before committing."
    fi

    # If the file is a JS file and it doesn't have a minified version, abort the commit.
    if [[ "${file}" == *.js ]] && [[ "${file}" != *.min.js ]] && ! has_minified_version "${file}"; then
        error_exit "JS file ${file} doesn't have a minified version!"
    fi

    # If the file is a minified JS file and it isn't as small as it can be, abort the commit.
    # Error message shows which minifier is best for the file.
    if [[ "${file}" == *.min.js ]]; then
        is_minified "${file}"
    fi
done

# Get the modified .md to update the "updated" field in the front matter.
modified_md_files=$(git diff --cached --name-only --diff-filter=M | grep -E '\.md$')

# Loop through each modified .md file.
for file in $modified_md_files; do
echo ${file}
    # If the file is an .md file and it's a draft, abort the commit.
    if is_draft "${file}"; then
        error_exit "Draft file ${file} is being committed!"
    fi

    # If changes are only in the front matter, skip the file.
    if ! has_body_changes "${file}"; then
        continue
    fi

    # Modify the "updated" date, if necessary.
    # Get the last modified date from the filesystem.
    last_modified_date=$(date -r "${file}" +'%Y-%m-%d')

    # Extract the "date" field from the front matter.
    date_value=$(extract_date "${file}" "date")

    # Skip the file if the last modified date is the same as the "date" field.
    if [[ "$last_modified_date" == "$date_value" ]]; then
        continue
    fi

    # Update the "updated" field with the last modified date.
    # If the "updated" field doesn't exist, create it below the "date" field.
    if ! awk -v date_line="$last_modified_date" 'BEGIN{FS=OFS=" = "; first = 1} {
        if (/^date =/ && first) {
            print; getline;
            if (!/^updated =/) print "updated" OFS date_line;
            first=0;
        }
        if (/^updated =/ && !first) gsub(/[^ ]*$/, date_line, $2);
        print;
    }' "${file}" > "${file}.tmp"
    then
        error_exit "Failed to process ${file} with AWK"
    fi

    mv "${file}.tmp" "${file}" || error_exit "Failed to overwrite ${file} with updated content"

    # Stage the changes.
    git add "${file}"

done

######################################################################
# Run ./scripts/subset-font.sh if config.toml has been modified.     #
# https://welpo.github.io/tabi/blog/custom-font-subset/              #
######################################################################
if git diff --cached --name-only | grep -q "config.toml"; then
    echo "config.toml modified. Attempting to run ./scripts/subset-font.sh…"

    # Check if ./scripts/subset-font.sh is available and exit early if not.
    if ! command -v subset-font.sh &> /dev/null; then
        echo "subset-font.sh command not found. Skipping this step."
        exit 0
    fi

    # Call the ./scripts/subset-font.sh script.
    ./scripts/subset-font.sh -c config.toml -f static/fonts/Inter4.woff2 -o static/

    # Add the generated subset.css file to the commit.
    git add static/custom_subset.css
fi

# Use `social-cards-zola.sh` to create/update the social media card for Markdown files.
# See https://osc.garden/blog/automating-social-media-cards-zola/ for context.
# Use parallel to create the social media cards in parallel and commit them.
if [ -z "$modified_md_files" ]; 
    then
        echo "no md files has been changed."; 
    else
        echo "$modified_md_files" | parallel -j 8 generate_and_commit_card; 
fi
