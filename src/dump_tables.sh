#!/bin/bash
. /opt/mssql_to_csv/mssql_vars.sh
. /opt/mssql_to_csv/mssql_lib.sh

set -x
list_tables | while read table; do
    dump_table "$table" > "/output/$table.csv"
    chmod 777 "/output/$table.csv"
done
