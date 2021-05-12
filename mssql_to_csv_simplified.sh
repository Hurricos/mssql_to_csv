#!/usr/bin/env bash

# import an MS SQL .bak backup file to an MS SQL database, then export all
# tables to csv. run this script as `import.sh <filename>`. It expects to be
# run in the same directory as the backup file.

# this is only tested on my mac (OS X Catalina). I tried to stick to posix, but
# It will probably require some tweaking for you. I hope it gives a general
# sense of what you need to do at the very least.

set -euxo pipefail

# the password for your user
# the name to give to the docker container

. src/mssql_vars.sh

if [[ -z ${1:-} ]]; then
    echo "Pass a .bak file as the first argument"
    exit 1
fi

rm -rf output;
mkdir -p output;
chmod 777 output;

# start a server if one isn't already running
if [[ -z $(docker ps -a -q -f "name=$CONTAINER_NAME") ]]; then
    docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$PASSWORD" \
      -p 1433:1433 --name "$CONTAINER_NAME" -v "${PWD}:/data" -v "${PWD}/output:/output" -v "${PWD}/src:/opt/mssql_to_csv" \
      -d mcr.microsoft.com/mssql/server:2019-GA-ubuntu-16.04
fi

# First we need to find out what filenames you have.
# this will print out a list of names and file location like:
# test_Data E:\Data\Dev1.mdf
# test_Log E:\Logs\Dev1.ldf
filelist=$(docker exec -it "$CONTAINER_NAME" /opt/mssql-tools/bin/sqlcmd -S localhost \
   -U SA -P "$PASSWORD" \
   -Q "RESTORE FILELISTONLY FROM DISK = \"/data/$1\"" |
   grep '^------' -A 100 | tail -n+2 | head -n-2 | sed -E 's/     +/^/g' | cut -d $'^' -f1-2)

# create a series of "WITH MOVE" statements, to tell MS SQL how to import each
# file
moves=""
while IFS=^ read table file rest; do
    # turn c:\dir\path\somefile.mdf to somefile.mdf
    filename=$(echo "$file" | sed -E 's/^.*\\([^\\]*)$/\1/g;')
    if [[ -z $moves ]]; then
        moves="WITH MOVE \"$table\" TO \"/var/opt/mssql/data/$filename\""
    else
        moves="$moves, MOVE \"$table\" TO \"/var/opt/mssql/data/$filename\""
    fi
done <<< "$filelist"

# import the database into MS SQL
docker exec -it "$CONTAINER_NAME" /opt/mssql-tools/bin/sqlcmd -S localhost \
   -U SA -P "$PASSWORD" \
   -Q "RESTORE DATABASE $DATABASE FROM DISK = \"/data/$1\" $moves"

# for each table, dump the output to <tablename>.csv
docker exec "$CONTAINER_NAME" /opt/mssql_to_csv/dump_tables.sh
