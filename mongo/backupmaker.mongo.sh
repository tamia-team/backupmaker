#!/bin/bash

# 
# ## Synopis
#
# > A shell script and a Docker image to backup one or multiple Mongo databases, then optionally encrypt and compress it.
#
# ## License
#
# Copyright 2023 Tamia SAS, Saint-Etienne 42100, France 🇫🇷
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the “Software”), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED “AS IS,” WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
# Except as contained in this notice, the name of the "Tamia SAS" shall not be
# used in advertising or otherwise to promote the sale, use or other dealings in
# this Software without prior written authorization from the Tamia SAS company.
#


# Function to display help
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --host             MongoDB host (default: localhost)"
    echo "  -p, --port             MongoDB port (default: 27017)"
    echo "  -d, --database         Database name (required, multiple allowed)"
    echo "  -e, --environment      Environment name (default: env-\$dbhost)"
    echo "  -j, --project          Project name (required)"
    echo "  -o, --output           Output directory (default: /app/dumps)"
    echo "  -u, --user             MongoDB username (optional)"
    echo "  -w, --password         MongoDB password (optional)"
    echo "  -g, --gpg              GPG file for encryption (optional)"
    echo "  -?, --help             Display this help message"
    echo "Error Codes:"
    echo "  1: Missing required arguments"
    echo "  2: Invalid MongoDB connection"
    echo "  3: Dump failed"
    echo "  4: Encryption failed"
    echo "  5: Compression failed"
}

# Function to check MongoDB connection
check_mongo_connection() {
    if ! mongo --host $host --port $port --eval "db.stats()" > /dev/null 2>&1; then
        echo "Error: Unable to connect to MongoDB at $host:$port"
        exit 2
    fi
}

# Function to perform database dump
perform_dump() {
    local db=$1
    local timestamp=$(date +"%Y%m%dT%H%M%S")
    local filename="${timestamp}.${project}.${environment}.${db}.mongo"

    mongodump --host $host --port $port --db $db --out $output/${filename}
    if [ $? -ne 0 ]; then
        echo "Error: Failed to dump database $db"
        exit 3
    fi

    if [ ! -z "$gpg" ]; then
        gpg --batch --yes --passphrase-file $gpg -o $output/${filename}.gpg -c $output/${filename}
        if [ $? -ne 0 ]; then
            echo "Error: Failed to encrypt $filename"
            exit 4
        fi
        rm -f $output/${filename}
        filename="${filename}.gpg"
    fi

    bzip2 $output/${filename}
    if [ $? -ne 0 ]; then
        echo "Error: Failed to compress $filename"
        exit 5
    fi
}

# Main function
main() {
    # Default values
    host="localhost"
    port=27017
    environment=""
    project=""
    output="/app/dumps"
    user=""
    password=""
    gpg=""

    # Parse arguments
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            -h|--host) host="$2"; shift ;;
            -p|--port) port="$2"; shift ;;
            -d|--database) databases+=("$2"); shift ;;
            -e|--environment) environment="$2"; shift ;;
            -j|--project) project="$2"; shift ;;
            -o|--output) output="$2"; shift ;;
            -u|--user) user="$2"; shift ;;
            -w|--password) password="$2"; shift ;;
            -g|--gpg) gpg="$2"; shift ;;
            -?|--help) show_help; exit 0 ;;
            *) echo "Unknown option: $1"; show_help; exit 1 ;;
        esac
        shift
    done

    # Validate required arguments
    if [ -z "$project" ] || [ ${#databases[@]} -eq 0 ]; then
        echo "Error: Missing required arguments"
        show_help
        exit 1
    fi

    # Set environment if not provided
    [ -z "$environment" ] && environment="env-$host"

    # Check MongoDB connection
    check_mongo_connection

    # Perform dumps
    for db in "${databases[@]}"; do
        perform_dump $db
    done
}

# Call main function with all arguments
main "$@"

