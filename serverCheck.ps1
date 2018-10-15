<#
    Code Notes:
    Program clears status file then itertates though services file content 
    checking desired computer for active processes. Will output resulting 
    process name if a match is found.
    Out-File arguments prevent file from getting overwritten, ensures appending
    and makes sure to encode in ascii values.
    Errors are output to log file and submitted to the MySQL DB.
    An email is sent to IT to notify them of the downtime.

#>
#Load all Initial content
$errorLog   = "" # Error log text location
$prevErrors = "" # Previous Errors locations
$server     = Get-Content -Path #Fill with response file from server.
$services   = Import-Csv -Path #Path to csv file, change headings# -Header process, display
$status     = "" # Path to status file

function insertLog($list){
    #create query string value and upload to MySQL
    Try{
        $stringData = New-Object System.Text.StringBuilder
        foreach($item in $list){
            [void]$stringData.Append("$item")
        }
        $date = Get-Date
        [void]$stringData.AppendLine(" could not be found running. Time: $date")
        $queryString = $stringData.ToString()

        $MySQLAdminUserName = ''
        $MySQLAdminPassword = ''
        $MySQLDatabase = ''
        $MySQLHost = ''
        $query = "INSERT INTO #table (errorReport) VALUES ('$queryString');"
        $ConnectionString = "server=" + $MySQLHost + ";SslMode=none;port=##;uid=" + $MySQLAdminUserName + ";pwd=" + $MySQLAdminPassword + ";database="+$MySQLDatabase;
        [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")
        $mysqlConn = New-Object -TypeName MySql.Data.MySqlClient.MySqlConnection
        $mysqlConn.ConnectionString = $ConnectionString
        $mysqlConn.Open()
        $MysqlQuery = New-Object -TypeName MySql.Data.MySqlClient.MySqlCommand($query ,$mysqlConn)
        [void]$MysqlQuery.ExecuteNonQuery()
        Write-Host "Entry Added"
    } Catch {
        Write-Host "Error when making database entry."
    }
}

#email settings
function sendEmail($list){
    $Username = "";
    $Password = "";
    $message = new-object Net.Mail.MailMessage;
    $message.From = "";
    $message.To.Add("");
    $message.Subject = "Note: Service is down";
    $message.IsBodyHtml = $true
    $message.Body = emailBody($list);

    $smtp = new-object Net.Mail.SmtpClient("", "");
    $smtp.Credentials = New-Object System.Net.NetworkCredential($Username, $Password);
    $smtp.Send($message);
    Write-Host "Mail Sent" ; 
}
#Create variable email data and add to here-string
function emailBody($list) {
    $stringBuilder = New-Object System.Text.StringBuilder
    $data = ""
    foreach($item in $list){
        $data = $stringBuilder.Append("<tr><td>$item</td></tr>")
    }
    $html = @"
    <!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
    <html>
    <style type="text/css">
	    #outlook a {padding:0;}
	    body{width:100% !important; -webkit-text-size-adjust:100%; -ms-text-size-adjust:100%; margin:0; padding:0;}
	    .ExternalClass {width:100%;} .ExternalClass, .ExternalClass p, .ExternalClass span, .ExternalClass font, .ExternalClass td, .ExternalClass div {line-height: 100%;}
	    @media only screen and (min-width: 600px) { .maxW { width:600px !important; } }
    </style>
    <meta http-equiv="Content-Type" content="text/html charset=UTF-8" />
    <head></head>
    <body style="-webkit-text-size-adjust:none; -ms-text-size-adjust:none;" leftmargin="0" topmargin="0" marginwidth="0" marginheight="0" bgcolor="#FFFFFF">
	    <table bgcolor="#CCCCCC" width="100%" height="100%" border="0" align="center"><tr><td valign="top">
           <table width="600px" height="80%" border="0" bgcolor="#FFFFFF" align="center" style="border-collapse:separate;padding:1rem; border-spacing: 10px 5px;box-shadow: 3px 7px 5px 0px rgba(0,0,0,0.75);">
			    <tr>
				    <td style="text-align: center; font-family: Verdana, Geneva,  sans-serif; font-size: 12px;"><h1> Server/Service Status</h1></td>
			    </tr>
			    <tr>
				    <td style="text-align: left; font-family: Verdana, Geneva,  sans-serif; font-size: 12px;">Hello IT,</td>
			    </tr>
			    <tr>
				    <td style="text-align:left; font-family: Verdana, Geneva, sans-serif; font-size: 12px;">
					    There was an error recorded by the automated status page. Please investigate investigate the issues regarding the following service(s)
				    </td>
			    <tr>
				    <td><h3>Service Issues:</h3></td>
			    </tr>
		        $data
		    </table>
	    </table>
    </body>
    </html>
"@
Return $html
}

$downList = New-Object System.Collections.ArrayList
$MysqlLog = New-Object System.Collections.ArrayList
$errorlog = New-Object System.Text.StringBuilder

$prevStatus = Get-Content -Path $status | Out-String
$prevErr    = Get-Content -Path $prevErrors | Out-String
"" | Out-File $status -NoNewline -Encoding ASCII
"" | Out-File $prevErrors -NoNewline -Encoding ASCII
Foreach ($service in $services) { 
    [void]$MysqlLog.Clear() 
    Try {
    $result = Get-Service -ComputerName $server $service."process" -EA Stop
    $name =  $result."Name"
        
    If($result.Status -eq "Running") {
        $name | Out-File $status -NoClobber -Append -Encoding ascii
    }
    } Catch {
        If($downList.Count -eq 0){
            [void]$errorLog.Append("Service(s) " + $service."process")
        } Else {
            [void]$errorLog.Append(", " + $service."process")
        }
        $string = "$("Service ")$($service."process")$(" could not be found running. Time: ")$(Get-Date)"
        $service."process" | Out-File $prevErrors -Append -NoClobber -Encoding ascii
        #Text-File Logging
        Write-Host $string
        $string | Out-File $errorLog -Append -NoClobber -Encoding ascii

        [void]$downList.Add($string)
        [void]$MysqlLog.Add($errorLog)
    }
}
#Compare new status page with old assign proper tasks
$newStatus = Get-Content -Path $status | Out-String
$sc = Out-String -InputObject $services."process"
If($sc.Length -ne $newStatus.Length){
    If($newStatus.Length -ne $prevStatus.Length){
        #sendEmail($downList)
        #insertLog($MysqlLog, 'down')
        Write-Host 'New Down'
    } Else {
        Write-Host 'Still Down'
    }
        
} ElseIf($sc.Length -eq $newStatus.Length){
    If($newStatus.Length -gt $prevStatus.Length){
        #sendEmail($downList)
        #insertLog($MysqlLog, 'back up')
        Write-Host 'Fixed'
    } Else {
        Write-Host 'All Good'
    }
}

