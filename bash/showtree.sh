#!/bin/bash

show_tree() {
    local path="${1:-.}"
    local prefix="${2:-}"
    local show_files="${3:-true}"
    local max_depth="${4:--1}"
    local current_depth="${5:-0}"
    
    # Check if maximum depth has been reached
    if [ "$max_depth" -ne -1 ] && [ "$current_depth" -ge "$max_depth" ]; then
        return
    fi
    
    # Get all items in the directory, sort directories first
    local items=()
    while IFS= read -r -d '' item; do
        items+=("$item")
    done < <(find "$path" -maxdepth 1 -mindepth 1 -print0 | sort -z)
    
    local count=${#items[@]}
    
    for ((i=0; i<count; i++)); do
        local item="${items[$i]}"
        local basename=$(basename "$item")
        local is_last=$((i == count - 1))
        
        # Determine connector character
        if [ $is_last -eq 1 ]; then
            local connector="└── "
            local extension="    "
        else
            local connector="├── "
            local extension="│   "
        fi
        
        # Display item
        if [ -d "$item" ]; then
            echo -e "${prefix}${connector}\033[0;36m${basename}/\033[0m"
            # Recursively display directory contents
            show_tree "$item" "${prefix}${extension}" "$show_files" "$max_depth" $((current_depth + 1))
        elif [ "$show_files" = "true" ]; then
            echo -e "${prefix}${connector}\033[0;37m${basename}\033[0m"
        fi
    done
}

# Usage Examples:
# show_tree                                    # Show the tree structure of the current directory
# show_tree "/home/user"                       # Show the tree structure of a specified path
# show_tree "." "" "false"                     # Show only directories, hide files
# show_tree "." "" "true" 2                    # Show tree structure up to a maximum depth of 2

# Call the function with command line arguments if provided
show_tree "$@"
