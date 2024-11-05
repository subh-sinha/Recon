#!/bin/bash

# Function to display help
show_help() {
    echo "Usage: $0 <url_or_file> [options]"
    echo
    echo "This script finds subdomains, live subdomains, endpoints, runs Nuclei, and finds ports."
    echo
    echo "Arguments:"
    echo "  <url_or_file>     A URL or a file containing a list of domains to process."
    echo
    echo "Options:"
    echo "  -s, --subdomains      Find subdomains."
    echo "  -h, --httpx           Run httpx to find live subdomains."
    echo "  -n, --nuclei          Run Nuclei on live subdomains."
    echo "  -p, --portscan        Find open ports on subdomains."
    echo "  -e, --endpoints       Find endpoints using WaybackURLs."
    echo "  -c, --clean           Clean the output directory."
    echo "  -o, --compare         Compare current results with previous results."
    echo "  -h, --help            Show this help message and exit."
}

# Variables
output_dir="output"
current_date=$(date +"%Y-%m-%d")
subdomains_file="$output_dir/subdomains_$current_date.txt"
live_subdomains_file="$output_dir/live_subdomains_$current_date.txt"
endpoints_file="$output_dir/endpoints_$current_date.txt"
nuclei_results_file="$output_dir/nuclei_results_$current_date.txt"
ports_file="$output_dir/ports_$current_date.txt"
new_subdomains_file="$output_dir/new_subdomains_$current_date.txt"

# Create output directory
mkdir -p "$output_dir"

# Function to clean output directory
clean_output() {
    echo "Cleaning output directory..."
    rm -rf "$output_dir"/*
}

# Function to compare subdomains with the previous day's results
compare_results() {
    previous_file=$(ls "$output_dir"/subdomains_*.txt 2>/dev/null | grep -v "$current_date" | tail -n 1)
    if [[ -f $previous_file ]]; then
        echo "Comparing current results with previous results..."
        comm -23 <(sort "$subdomains_file") <(sort "$previous_file") > "$new_subdomains_file"

        if [[ -s $new_subdomains_file ]]; then
            echo "New subdomains found:"
            cat "$new_subdomains_file"
        else
            echo "No new subdomains found."
        fi
    else
        echo "No previous subdomains file to compare."
    fi
}

# Function to find subdomains
find_subdomains() {
    echo "Finding subdomains for $1..."
    subfinder -d "$1" -o "$subdomains_file"
    assetfinder --subs-only "$1" >> "$subdomains_file"
    sublist3r -d "$1" -o "$subdomains_file"
    findomain -t "$1" -u "$subdomains_file"
    chaos -d "$1" -o "$subdomains_file"
    sort -u "$subdomains_file" -o "$subdomains_file"
}

# Function to find live subdomains
find_live_subdomains() {
    echo "Finding live subdomains for $1..."
    httpx -l "$subdomains_file" -o "$live_subdomains_file"
}

# Function to run Nuclei on live subdomains
run_nuclei() {
    echo "Running Nuclei for $1..."
    proxychains nuclei -l "$live_subdomains_file" -t ~/nuclei-templates/http/exposures/ -o "$nuclei_results_file"
}

# Function to find open ports
find_ports() {
    echo "Finding ports for $1..."
    proxychains naabu -l "$live_subdomains_file" -o "$ports_file"
}

# Function to find endpoints
find_endpoints() {
    echo "Finding endpoints for $1..."
    proxychains katana -d "$live_subdomains_file" -o "$endpoints_file"
    cat "$live_subdomains_file" | waybackurls | tee -a "$endpoints_file"
    proxychains sro -l "$live_subdomains_file" -o "$endpoints_file"
}

# Function to process input file or URL
process_input() {
    input=$1
    if [[ -f $input ]]; then
        while IFS= read -r domain; do
            echo "Processing domain: $domain"
            run_operations "$domain"
        done < "$input"
    else
        echo "Processing domain: $input"
        run_operations "$input"
    fi
}

# Function to run operations based on provided flags
run_operations() {
    domain=$1
    [[ "$run_subdomains" == true ]] && find_subdomains "$domain"
    [[ "$run_httpx" == true ]] && find_live_subdomains "$domain"
    [[ "$run_nuclei" == true ]] && run_nuclei "$domain"
    [[ "$run_ports" == true ]] && find_ports "$domain"
    [[ "$run_endpoints" == true ]] && find_endpoints "$domain"
}

# Parse options
run_subdomains=false
run_httpx=false
run_nuclei=false
run_ports=false
run_endpoints=false
clean_output_option=false
compare_results_option=false

while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--subdomains)
            run_subdomains=true
            shift
            ;;
        -h|--httpx)
            run_httpx=true
            shift
            ;;
        -n|--nuclei)
            run_nuclei=true
            shift
            ;;
        -p|--portscan)
            run_ports=true
            shift
            ;;
        -e|--endpoints)
            run_endpoints=true
            shift
            ;;
        -c|--clean)
            clean_output_option=true
            shift
            ;;
        -o|--compare)
            compare_results_option=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            if [[ -z "$input" ]]; then
                input="$1"
            else
                echo "Unknown option: $1"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# Check if input is provided
if [[ -z "$input" ]]; then
    echo "No domain or file provided."
    show_help
    exit 1
fi

# Clean output or compare results
if $clean_output_option; then
    clean_output
elif $compare_results_option; then
    compare_results
fi

# Check if at least one operation option is provided
if ! $run_subdomains && ! $run_httpx && ! $run_nuclei && ! $run_ports && ! $run_endpoints; then
    echo "At least one operation option must be provided."
    show_help
    exit 1
fi

# Run selected operations
process_input "$input"

echo "Process completed! All results are stored in $output_dir."
