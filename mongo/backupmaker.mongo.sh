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

#!/bin/bash

# Script to backup MongoDB databases

# Default values
DEFAULT_HOST="localhost"
DEFAULT_PORT="27017"
DEFAULT_DEST_DIR="/app/dumps"
DEFAULT_ENV_PREFIX="BACKUPMAKER_"

# Function to print help
function print_help {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -h, --host               MongoDB host (default: localhost)"
    echo "  -p, --port               MongoDB port (default: 27017)"
    echo "  -d, --database           Name of the database to dump (required)"
    echo "  -e, --environment        Backup environment (default: env-\$dbhost)"
    echo "  -j, --project            Project name (required)"
    echo "  -r, --destination        Destination directory (default: /app/dumps)"
    echo "  -u, --user               MongoDB user (optional)"
    echo "  -w, --password           MongoDB password (optional)"
    echo "  -g, --gpg-file           GPG key file for encryption (optional)"
    echo "  -s, --aws-s3-path        AWS S3 bucket path for sync (optional)"
    echo "  -a, --access-key         AWS S3 access key (required if S3 path is set)"
    echo "  -k, --secret-key         AWS S3 secret key (required if S3 path is set)"
    echo "  -f, --help               Display this help message"
    exit 0
}

# Function to install dependencies
function install_dependencies {
    # Determine OS and install dependencies accordingly
    local os=$(awk -F= '/^ID=/{print $2}' /etc/os-release)
    
    case "$os" in
        "debian"|"ubuntu")
            sudo apt-get update
            sudo apt-get install -y mongodb-org-tools bzip2 gnupg awscli
            ;;
        "alpine")
            sudo apk add mongodb-tools bzip2 gnupg aws-cli
            ;;
        "centos")
            sudo yum install -y mongodb-org-tools bzip2 gnupg awscli
            ;;
        *)
            echo "Unsupported OS"
            exit 1
            ;;
    esac
}

# Function to parse arguments
function parse_args {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--host)
                HOST="$2"
                shift # past argument
                shift # past value
                ;;
            -p|--port)
                PORT="$2"
                shift
                shift
                ;;
            -d|--database)
                DATABASES+=("$2")
                shift
                shift
                ;;
            -e|--environment)
                ENVIRONMENT="$2"
                shift
                shift
                ;;
            -j|--project)
                PROJECT="$2"
                shift
                shift
                ;;
            -r|--destination)
                DEST_DIR="$2"
                shift
                shift
                ;;
            -u|--user)
                USER="$2"
                shift
                shift
                ;;
            -w|--password)
                PASSWORD="$2"
                shift
                shift
                ;;
            -g|--gpg-file)
                GPG_FILE="$2"
                shift
                shift
                ;;
            -s|--aws-s3-path)
                AWS_S3_PATH="$2"
                shift
                shift
                ;;
            -a|--access-key)
                AWS_ACCESS_KEY="$2"
                shift
                shift
                ;;
            -k|--secret-key)
                AWS_SECRET_KEY="$2"
                shift
                shift
                ;;
            -f|--help)
                print_help
                ;;
            *)
                echo "Invalid argument: $1"
                print_help
                ;;
        esac
    done

    # Validate required arguments
    if [ -z "$PROJECT" ]; then
        echo "Project name is required"
        exit 2
    fi

    if [ ${#DATABASES[@]} -eq 0 ]; then
        echo "At least one database name is required"
        exit 3
    fi

    # Apply default values from environment variables if not set
    HOST="${HOST:-${!DEFAULT_ENV_PREFIX}HOST}"
    PORT="${PORT:-${!DEFAULT_ENV_PREFIX}PORT}"
    DEST_DIR="${DEST_DIR:-${!DEFAULT_ENV_PREFIX}DEST_DIR}"
    USER="${USER:-${!DEFAULT_ENV_PREFIX}USER}"
    PASSWORD="${PASSWORD:-${!DEFAULT_ENV_PREFIX}PASSWORD}"
    GPG_FILE="${GPG_FILE:-${!DEFAULT_ENV_PREFIX}GPG_FILE}"
    AWS_S3_PATH="${AWS_S3_PATH:-${!DEFAULT_ENV_PREFIX}AWS_S3_PATH}"
    AWS_ACCESS_KEY="${AWS_ACCESS_KEY:-${!DEFAULT_ENV_PREFIX}AWS_ACCESS_KEY}"
    AWS_SECRET_KEY="${AWS_SECRET_KEY:-${!DEFAULT_ENV_PREFIX}AWS_SECRET_KEY}"

    # Set defaults
    HOST="${HOST:-$DEFAULT_HOST}"
    PORT="${PORT:-$DEFAULT_PORT}"
    DEST_DIR="${DEST_DIR:-$DEFAULT_DEST_DIR}"
}

# Function to perform MongoDB dump
function mongo_dump {
    local db="$1"
    local timestamp=$(date +%Y%m%dT%H%M%S)
    local filename="${timestamp}.${PROJECT}.${ENVIRONMENT:-env-$HOST}.${db}.mongo.dump.bz2"
    local filepath="${DEST_DIR}/${filename}"

    # Dump and compress database
    mongodump --host "$HOST" --port "$PORT" --db "$db" ${USER:+--username "$USER"} ${PASSWORD:+--password "$PASSWORD"} --archive | bzip2 > "$filepath"

    # Check for errors in mongodump
    if [ $? -ne 0 ]; then
        echo "Error in dumping database: $db"
        exit 4
    fi

    # Encrypt file if GPG key is provided
    if [ -n "$GPG_FILE" ]; then
        gpg --batch --yes --encrypt --recipient-file "$GPG_FILE" "$filepath"
        if [ $? -ne 0 ]; then
            echo "Error in encrypting database dump: $db"
            exit 5
        fi
        rm "$filepath"
    fi
}

# Function to sync with AWS S3
function sync_s3 {
    if [ -n "$AWS_S3_PATH" ]; then
        if [ -z "$AWS_ACCESS_KEY" ] || [ -z "$AWS_SECRET_KEY" ]; then
            echo "AWS S3 Access Key and Secret Key are required"
            exit 6
        fi

        export AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY"
        export AWS_SECRET_ACCESS_KEY="$AWS_SECRET_KEY"

        aws s3 sync "$DEST_DIR" "$AWS_S3_PATH"
        if [ $? -ne 0 ]; then
            echo "Error in syncing with AWS S3"
            exit 7
        fi
    fi
}

# Main function
function main {
    install_dependencies
    parse_args "$@"

    # Loop through databases and perform dump
    for db in "${DATABASES[@]}"; do
        mongo_dump "$db"
    done

    sync_s3
}

# Call main function with all passed arguments
main "$@"

