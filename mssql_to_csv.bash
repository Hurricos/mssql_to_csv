#!/usr/bin/env bash

# import an MS SQL .bak backup file to an MS SQL database, then export all
# tables to csv. run this script as `import.sh <filename>`. It expects to be
# run in the same directory as the backup file.

# this is only tested on my mac (OS X Catalina). I tried to stick to posix, but
# It will probably require some tweaking for you. I hope it gives a general
# sense of what you need to do at the very least.

set -euxo pipefail

# the database name you want to create
DATABASE="restore"
# the password for your user
PASSWORD="<YourStrong@Passw0rd>"
# the name to give to the docker container
NAME=sqlbackup

if [[ -z ${1:-} ]]; then
    echo "Pass a .bak file as the first argument"
    exit 1
fi

# start a server if one isn't already running
if [[ -z $(docker ps -q -f "name=$NAME") ]]; then
    docker run -e "ACCEPT_EULA=Y" -e "SA_PASSWORD=$PASSWORD" \
      -p 1433:1433 --name "$NAME" -v "${PWD}:/data" \
      -d mcr.microsoft.com/mssql/server:2019-GA-ubuntu-16.04
fi

# First we need to find out what filenames you have.
# this will print out a list of names and file location like:
# test_Data E:\Data\Dev1.mdf
# test_Log E:\Logs\Dev1.ldf
filelist=$(docker exec -it "$NAME" /opt/mssql-tools/bin/sqlcmd -S localhost \
   -U SA -P "$PASSWORD" \
   -Q "RESTORE FILELISTONLY FROM DISK = \"/data/$1\"" \
   | tr -s ' ' | cut -d ' ' -f 1-2 | sed -e '$ d' | sed -e '$ d' | tail -n+3)

# create a series of "WITH MOVE" statements, to tell MS SQL how to import each
# file
moves=""
while IFS= read -r line; do
    parts=($line)
    # turn c:\dir\path\somefile.mdf to somefile.mdf
    filename=$(echo "${parts[1]}" | sed -E 's/^.*\\([^\\]*)$/\1/g')
    if [[ -z $moves ]]; then
        moves="WITH MOVE \"${parts[0]}\" TO \"/var/opt/mssql/data/$filename\""
    else
        moves="$moves, MOVE \"${parts[0]}\" TO \"/var/opt/mssql/data/$filename\""
    fi
done <<< "$filelist"

# import the database into MS SQL
docker exec -it "$NAME" /opt/mssql-tools/bin/sqlcmd -S localhost \
   -U SA -P "$PASSWORD" \
   -Q "RESTORE DATABASE $DATABASE FROM DISK = \"/data/$1\" $moves"

# list the tables in the database you just created
# requires bash >= 4
mapfile -t tables < <(docker exec -it "$NAME" /opt/mssql-tools/bin/sqlcmd -S localhost \
    -U SA -P "$PASSWORD" \
    -Q "SELECT table_schema+'.'+table_name FROM $DATABASE.INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE'" \
    | tail -n+3 | sed -e '$ d' | sed -e '$ d' | tr -d ' ')

# for each table, dump the output to <tablename>.csv
for table in "${tables[@]}"
do
    docker exec -it "$NAME" /opt/mssql-tools/bin/bcp \
        "select * from $DATABASE.$table" queryout "/data/$table.csv" \
        -S localhost -U SA -P "$PASSWORD" -t, -c
done
