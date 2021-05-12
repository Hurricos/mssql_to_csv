
function list_tables {
    # for each table, dump the output to <tablename>.csv
    sqlcmd -S localhost \
           -U "SA" -P "$PASSWORD" \
           -Q "SELECT table_schema+'.'+table_name FROM $DATABASE.INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE = 'BASE TABLE'" |
        tail -n+3 | sed -e '$ d' | sed -e '$ d' | tr -d ' \r'
}

function dump_table {
    local table="$1";
    local subtable="${table#*.}"
    
    tmph="$(mktemp -p /output --suffix=.csv)"
    tmpf="$(mktemp -p /output --suffix=.csv)"

    bcp "DECLARE @colnames VARCHAR(max);SELECT @colnames = COALESCE(@colnames + '#@RSEP@#', '') + column_name from $DATABASE.INFORMATION_SCHEMA.COLUMNS where TABLE_NAME='$subtable'; select @colnames;" \
        queryout "$tmph" -c -S localhost -U "SA" -P "$PASSWORD" -t "#@RSEP@#" -r "
#@LSEP@#" >&2
    
    bcp "select * from $DATABASE.$table" queryout "$tmpf" -S localhost -U "SA" -P "$PASSWORD" -t "#@RSEP@#" -r "^#@LSEP@#" -c >&2

    cat "$tmph" "$tmpf" | tr -d '\001' | tr '^' '\n' | sed 's/^#@LSEP@#/\x01/g' | tr '\001\n' '\n\001' | sed 's/#@RSEP@#/^/g' | sed 's/\x01$//' | sed 's/\x01/\\n/g'
    rm "$tmph" "$tmpf"
}
