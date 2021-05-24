class PsMySQL
{
    hidden $connection
    hidden [string] $table
    hidden [string] $columns
    hidden [string] $where
    hidden [string] $query
    hidden [string] $joins
    hidden [string] $debugFile
    hidden [bool] $debugMode = $false
    [System.Object] $lastError

    PsMySQL([string]$assemblyPath){
        [system.reflection.Assembly]::LoadFrom($assemblyPath)
    }

    PsMySQL([string]$assemblyPath, [string] $debugFilePath){        
        $this.debugMode = $true
        # debug file exists
        if(!(Test-Path $debugFilePath)){
            TRY{
                New-Item -ItemType f -Path $debugFilePath -Force -ErrorAction Stop
                $this.debugFile = $debugFilePath
            } CATCH {
                $appF = 'C:\ProgramData\PsMySQL'
                if(!(Test-Path $appF)){
                    New-Item -ItemType d -Path $appF -Force | Out-Null
                    New-Item -ItemType f -Path "$appF\debug.log" -Force | Out-Null
                }
                if (!(Test-Path "$appF\debug.log")){ New-Item -ItemType f -Path "$appF\debug.log" -Force | Out-Null }
                $this.debugFile = "$appF\debug.log"
            }
        } else {
            $this.debugFile = $debugFilePath
        }

        TRY{
            [system.reflection.Assembly]::LoadFrom($assemblyPath)
        } CATCH {
            $this.debug($Error[0])
        }
    }

   [PsMySQL] connectAs(
    [string] $server, 
    [string] $name,
    [string] $secret,
    [string] $db,
    [string] $sslMode)
   {
    $string = 'server=' + $server + ';uid=' + $name + ';pwd=' + $secret + ';database=' + $db + ';SslMode=' + $sslMode
    $this.connection = @{
        ConnectionString=$string
    }
    return $this
   }

   [PsMySQL] on([string] $table){
        $this.table = $table
        $this.where = $null
        $this.joins = $null
        return $this
    }

   [PsMySQL] choose([array] $columns){
        $col = ""

        for ($i = 0; $i -lt $columns.Count; $i++) {
            # column rename
            if ($columns[$i] -like '*(*') {
                $field = (($columns[$i] -split "\(")[0]).ToString().Trim()
                $rgx = [regex]"\((.*)\)"
                $as = [regex]::Match($columns[$i], $rgx).Groups[1]
                $col += "$field AS $as"
            } else {
                $col += ($columns[$i]).ToString().Trim()
            }            
            # add comma
            if ($i -ne ($columns.Count - 1)) {
                $col += ', '
            }
        }#--for

        $this.columns = $col
        $this.debug(".choose() => " + $col)
        return $this
    }

   [PsMySQL] find([array] $where){
        $wh = ''
        $joiner = $null
        for ($i = 0; $i -lt $where.Count; $i++) {
            if ($where[$i] -like '&') {
               $joiner = 'AND'
               continue
            }

            if ($where[$i] -like '|') {
                $joiner = 'OR'
                continue
            }
            $str = $this.whereBuilder($where[$i])
            $wh+=$str
            
            # not the last item and arr more than 2
            if (($i -ne ($where.Count - 1)) -and ($where.Count -gt 2)) {
                $wh += " $joiner "
            }
        }
        $this.where=$wh
        $this.debug(".find() WHERE => " + $wh)
        return $this
    }

   [PsMySQL] rawQuery([string] $query){
        $this.query = $query
        $this.where = $null
        $this.joins = $null
        $this.debug(".rawQuery() => " + $query)
        return $this
    }

   [System.Object] execute(){ # execute raw queries
        $this.debug(".execute() QUERY => " + $this.query)
        return $this.reader($this.query)[-1]
    }

    [System.Object] load(){ # build SQL statement
        $q = "SELECT $($this.columns) FROM $($this.table)"
        if($this.joins) {$q += $this.joins }
        if ($this.where) { $q += " WHERE $($this.where)" }        
        $this.query = $q        
        #clear where & joins
        $this.where = $null
        $this.joins = $null
        $this.debug(".load() QUERY => " + $q)
        return $this.execute()
    }

    [PsMySQL] commit([array] $data){
        $this.debug('.commit() STRING => ' + $data -join '*')
        $cols = '('
        $vals = 'VALUES ('
        for ($i = 0; $i -lt $data.Count; $i++) {
            $splt = $data[$i] -split ':='
            $cols += "``$(($splt[0]).ToString().Trim())``"
            $vals += "'" + $this.mySqlEscapeString(($splt[1]).ToString().Trim()) + "'"

            # not the last item add ,
            if ($i -ne ($data.Count - 1)) {
                $cols+= ', '
                $vals+= ', '
            }            
        }
        $cols+=')'
        $vals+=')'
        $this.query = "INSERT INTO ``$($this.table)`` $cols $vals"
        # clear
        $this.where = $null
        $this.debug(".commit() QUERY => " + $this.query)
        return $this
    }

    [PsMySQL] set([array] $values){
        $this.debug('.set() VALUES => ' + $values -join '*')
        $setVals = ''
        for ($i = 0; $i -lt $values.Count; $i++) {
            $spl = $values[$i] -split ','
            $col = $spl[0]

            $vrgx = [regex]"\((.*)\)"
            $val = [regex]::Match($values[$i], $vrgx).Groups[1]

            $val = "'" + $this.mySqlEscapeString($val) + "'"

            $setVals += "$($col.ToString().Trim())=$($val.ToString().Trim())"

            # add comma
            if ($i -ne ($values.Count - 1)) {
                $setVals += ', '
            }
        }#--for

        $this.query = "UPDATE $($this.table) SET $setVals WHERE $($this.where)"
        $this.debug(".set() QUERY => " + $this.query)
        return $this
    }


   [bool] save(){
        if ($this.query -eq $null){
            $this.debug(".save() ERROR => Query string null or empty. Preceed with commit()")
            return $false
        }
        $save = $this.nonQuery($this.query)
        $this.query = $null
        $this.debug(".save() RETURN => " + $save.ToString())
        return $save
    }

   [bool] trash(){
        $this.query = "DELETE FROM $($this.table) WHERE $($this.where)"
        $this.debug(".trash() QUERY => " + $this.query)
        $trash = $this.nonQuery($this.query)
        $this.query = $null
        $this.debug(".trash() RETURN => " + $trash)
        return $trash
    }

    [bool] has(){
        $read = $this.load()
        $this.debug(".has() QUERY => " + $this.query)              
        return $read.Count -gt 0
    }

    # --- INTERNAL =============

    hidden [System.Object] reader([string] $query){
        if ($this.connection.State -eq 'Closed'){ $this.connection.Open() }
        $cmd = New-Object MySql.Data.MySqlClient.MySqlCommand($query, $this.connection)
      $dataAdapter = New-Object MySql.Data.MySqlClient.MySqlDataAdapter($cmd)
      $dataSet = New-Object System.Data.DataSet 

      TRY{
        $dataAdapter.Fill($dataSet, "data") 
      } CATCH {
        $this.debug(".reader() ERROR => " + $Error[0])
      }

      $cmd.Dispose()
      $result = $dataSet.Tables["data"]
      $response = @()

      foreach($i in $result){
        $cols = @()
        $col = $i.Table.Columns | select ColumnName
        foreach($j in $col){ $cols += $j.ColumnName }
        $eHash = @{}
        $cols | % { $eHash.Add($_, $null) }
        $obj = [pscustomobject]$eHash

        for ($l = 0; $l -lt $cols.count; $l++){ 
            $val = $i.Item($l)
            $obj."$($cols[$l])" = $val
        }#--for
        $response += $obj
      }#--%

      if($this.connection.State -eq 'Open'){ $this.connection.Close() }
      $this.debug(".reader() COUNT => " + $response.Count)
      return ,$response
    }

    hidden [bool] nonQuery([string] $query){
        $this.debug(".nonQuery() QUERY => " + $query)

        if($this.connection.State -eq 'Closed'){
            TRY{
                $this.connection.Open()
            } CATCH { $this.debug('.nonQuery() ERROR => ' + $Error[0]) }
        }
        
        $c = $this.connection.CreateCommand()
        $c.CommandText = $query

        TRY{
            $RowsInserted = $c.ExecuteNonQuery()
            $c.Dispose()
                   
            if($this.connection.State -eq 'Open'){
                TRY{$this.connection.Close()}
                CATCH { $this.debug('.nonQuery() ERROR => ' + $Error[0]) }
            }

            if ($RowsInserted){ return $true }
        } CATCH { $this.debug(".nonQuery() ERROR => " + $Error[0]) } 
        
        if($this.connection.State -eq 'Open'){
            TRY{$this.connection.Close()} 
            CATCH { $this.debug('.nonQuery() ERROR => ' + $Error[0]) }
        }      
         
        return $false
    }

    hidden [string] whereBuilder([string] $arg){
        $wh = ''
        $splt = $arg -split ','
        $k=$splt[0]
        $v=$splt[1]
        $rgx = [regex]"\[(.*)\]"
        $oprt = [regex]::Match($k, $rgx).Groups[1]
        $f = ($k -split '\[')[0]
        $vrgx = [regex]"\'(.*)\'"
        $val = [regex]::Match($v, $vrgx).Groups[1]

        if ($oprt -like "*~*") {
            switch ($oprt) {
                '>~' { $wh += "$f LIKE '$val%'"  }
                '<~' { $wh += "$f LIKE '%$val'" }
                Default { $wh += "$f LIKE '%$val%'" }
            }
        } 
        elseif ($oprt -like "*!*") {
            switch ($oprt) {
                '!=' { $wh += "$f <> '$val'"  }
                Default {
                  $wh = "$f NOT IN ("
                  $arr = $v -split ':'

                  for ($i = 0; $i -lt $arr.Count; $i++) {
                     $wh += $arr[$i]

                     if ($i -ne ($arr.Count - 1)) {
                        $wh += ', '
                    } 
                  }#--for
                  $wh += ')'
                }
            }
        } 
        elseif ($oprt -like '==') {
            $wh = "$f IN ("
                  $arr = $v -split ':'

                  for ($i = 0; $i -lt $arr.Count; $i++) {
                     $wh += $arr[$i]

                     if ($i -ne ($arr.Count - 1)) {
                        $wh += ', '
                    } 
                  }#--for
                  $wh += ')'
        } 
        else {
            $wh += "$f $oprt $($v.Trim())"
        }
        return $wh
    }

    hidden [string] joinType([string] $str){       
        if($str.Contains('-')){ return 'CROSS JOIN'}
        if($str.Contains('>')){ return 'RIGHT JOIN'}
        if($str.Contains('<')){ return 'LEFT JOIN'}
        return 'RIGHT JOIN'
    }

    hidden [void] debug([string] $message){
        if ($this.debugMode){
            "[$(Get-Date -UFormat '%Y-%m-%d %I:%M:%S')]:: $Message" | Out-File $this.debugFile -Force -Append
        }
    }

    hidden [string] mySqlEscapeString([string] $string){
        $replaced = $string.Replace("\","\\").Replace("'","\'")
        $this.debug('.mySqlEscapeString() FROM: ' + $string + ' TO: ' + $replaced)
        return $replaced
    }

}