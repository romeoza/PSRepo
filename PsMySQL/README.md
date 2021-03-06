# PsMySQL

PsMySQL is a [MySQL Connector/Net](https://dev.mysql.com/downloads/connector/net/) wrapper written in PowerShell.

## Installation

Download PsMySQL.ps1 and dot source 

## Usage

```powershell
.\PsMySQL.ps1
$psMYSQL = [PsMySQL]::new('C:\Program Files (x86)\MySQL\MySQL Connector Net 8.0.25\Assemblies\v4.5.2\MySql.Data.dll')
# With debugging
$psMYSQL = [PsMySQL]::new('C:\Program Files (x86)\MySQL\MySQL Connector Net 8.0.25\Assemblies\v4.5.2\MySql.Data.dll','path\to\debug\file.log')
$DB = $psMYSQL.connectAs('127.0.0.1','user','password','database','none')
```
### Raw Query
Execute a customized query

```powershell
$q = 'SELECT * FROM table1 WHERE id = 1'
$data = 
$DB.
rawQuery($q).
execute()
```

### Query
#### SELECT
Vanilla select
```powershell
$DB.
on('table_name').
choose(('col_one','col_two')). # You can use '*' to return all columns
load()
```
Column Alias
```powershell
$DB.
on('table_name').
choose((
    'col_one (first)',
    'col_two (second)'
)).
load()
```
#### WHERE
##### Basic Conditions

```powershell
# WHERE id = 2
$DB.
on('table_name').
choose(('col_one','col_two')).
find((
    "id[=], 2" # [condition]
)).
load()
<# Valid conditions
    "id[>], 2"[>]       # > 2
    "id[<], 2"[<>]      # < 2
    "id[>=], 2"         # >= 2
    "id[<=], 2"         # <= 2
    "id[!=], 2"         # != 2
#>
```
##### Advanced Conditions
```powershell
# WHERE id = 2 OR col_one 'ralph%'
$DB.
on('table_name').
choose(('col_one (firstName)','col_two (email)')).
find((
    "|",                # OR
    "id[=], 2",         # EQUAL
    "col_one[>~], ralp" # STARTS WITH
)).
load()
# WHERE id > 2 AND col_one '%ralph'
$DB.
on('table_name').
choose(('col_one (firstName)','col_two (email)')).
find((
    "&",                # AND
    "id[>], 2",         # GREATER THAN
    "col_one[<~], ralp" # ENDS WITH
)).
load()
<# Valid Conditions
    "name[~], Mat"              # %Mat%
    "id[!], 1:2:3"              # NOT IN (1,2,3)
    "id[==], jack:jim:jill"     # IN ('jack','jim','jill')
#>
```
#### INSERT
Vanilla Insert
```powershell
# INSERT INTO table_name (`col_one`,`col_two`,`col_three`) VALUES ('we escape a \'','we escape a \\',24)
$DB.
on('table_name').
commit((
    "col_one := we escape a '",
    "col_two := we escape a \",
    "col_three := 24"
)).
save()
```