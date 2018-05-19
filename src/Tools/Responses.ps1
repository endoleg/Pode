# write data to main http response
function Write-ToResponse
{
    param (
        [Parameter()]
        $Value,

        [Parameter()]
        [string]
        $ContentType = $null
    )

    if (![string]::IsNullOrWhiteSpace($ContentType)) {
        $PodeSession.Web.Response.ContentType = $ContentType
    }

    $writer = New-Object -TypeName System.IO.StreamWriter -ArgumentList $PodeSession.Web.Response.OutputStream
    $writer.WriteLine([string]$Value)
    $writer.Close()
}

function Status
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        [int]
        $Code,

        [Parameter()]
        [string]
        $Description
    )

    $PodeSession.Web.Response.StatusCode = $Code
    $PodeSession.Web.Response.StatusDescription = $Description
}

function Write-ToResponseFromFile
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Path
    )

    # if the file doesnt exist then just fail on 404
    if (!(Test-Path $Path)) {
        status 404
        return
    }

    # are we dealing with a dynamic file for the view engine?
    $ext = [System.IO.Path]::GetExtension($Path).Trim('.')
    if ((Test-Empty $ext) -or $ext -ine $PodeSession.ViewEngine.Extension) {
        $content = Get-Content -Path $Path -Raw
        Write-ToResponse -Value $content
        return
    }

    # generate dynamic content
    $content = [string]::Empty

    switch ($ext.ToLowerInvariant())
    {
        'pode' {
            $content = Get-Content -Path $Path -Raw
            $content = ConvertFrom-PodeFile -Content $content
        }

        default {
            if ($PodeSession.ViewEngine.Script -ne $null) {
                $content = Invoke-Command -ScriptBlock $PodeSession.ViewEngine.Script -ArgumentList $Path
            }
        }
    }

    Write-ToResponse -Value $content -ContentType (Get-DynamicContentType -Path $Path)
}

function Write-JsonResponse
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Value,

        [switch]
        $NoConvert
    )

    if (!$NoConvert) {
        $Value = ($Value | ConvertTo-Json -Depth 10 -Compress)
    }

    Write-ToResponse -Value $Value -ContentType 'application/json; charset=utf-8'
}

function Write-JsonResponseFromFile
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Path
    )

    if (!(Test-Path $Path)) {
        status 404
        return
    }

    $content = Get-Content -Path $Path
    Write-JsonResponse -Value $content -NoConvert
}

function Write-XmlResponse
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Value,

        [switch]
        $NoConvert
    )

    if (!$NoConvert) {
        $Value = ($Value | ConvertTo-Xml -Depth 10)
    }

    Write-ToResponse -Value $Value -ContentType 'application/xml; charset=utf-8'
}

function Write-XmlResponseFromFile
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Path
    )

    if (!(Test-Path $Path)) {
        status 404
        return
    }

    $content = Get-Content -Path $Path
    Write-XmlResponse -Value $content -NoConvert
}

function Write-HtmlResponse
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Value,

        [switch]
        $NoConvert
    )

    if (!$NoConvert) {
        $Value = ($Value | ConvertTo-Html)
    }

    Write-ToResponse -Value $Value -ContentType 'text/html; charset=utf-8'
}

function Write-HtmlResponseFromFile
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Path
    )

    if (!(Test-Path $Path)) {
        status 404
        return
    }

    $content = Get-Content -Path $Path
    Write-HtmlResponse -Value $content -NoConvert
}

# include helper to import the content of a view into another view
function Include
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNullOrEmpty()]
        [string]
        $Path,

        [Parameter()]
        $Data = @{}
    )

    # add view engine extension
    $ext = [System.IO.Path]::GetExtension($Path)
    $hasExt = ![string]::IsNullOrWhiteSpace($ext)
    if (!$hasExt) {
        $Path += ".$($PodeSession.ViewEngine.Extension)"
    }

    # only look in the view directory
    $Path = (Join-Path 'views' $Path)
    if (!(Test-Path $Path)) {
        throw "File not found at path: $($Path)"
    }

    # run any engine logic
    $engine = $PodeSession.ViewEngine.Extension
    if ($hasExt) {
        $engine = $ext.Trim('.')
    }

    $content = [string]::Empty

    switch ($engine.ToLowerInvariant())
    {
        'html' {
            $content = Get-Content -Path $Path -Raw
        }

        'pode' {
            $content = Get-Content -Path $Path -Raw
            $content = ConvertFrom-PodeFile -Content $content -Data $Data
        }

        default {
            if ($PodeSession.ViewEngine.Script -ne $null) {
                $content = Invoke-Command -ScriptBlock $PodeSession.ViewEngine.Script -ArgumentList $Path, $Data
            }
        }
    }

    return $content
}

function Write-ViewResponse
{
    param (
        [Parameter(Mandatory=$true)]
        [ValidateNotNull()]
        $Path,

        [Parameter()]
        $Data = @{}
    )

    # default data if null
    if ($Data -eq $null) {
        $Data = @{}
    }

    # add path to data as "pagename" - unless key already exists
    if (!$Data.ContainsKey('pagename')) {
        $Data['pagename'] = $Path
    }

    # add view engine extension
    $ext = [System.IO.Path]::GetExtension($Path)
    $hasExt = ![string]::IsNullOrWhiteSpace($ext)
    if (!$hasExt) {
        $Path += ".$($PodeSession.ViewEngine.Extension)"
    }

    # only look in the view directory
    $Path = (Join-Path 'views' $Path)
    if (!(Test-Path $Path)) {
        status 404
        return
    }

    # run any engine logic
    $engine = $PodeSession.ViewEngine.Extension
    if ($hasExt) {
        $engine = $ext.Trim('.')
    }

    $content = [string]::Empty

    switch ($engine.ToLowerInvariant())
    {
        'html' {
            $content = Get-Content -Path $Path -Raw
        }

        'pode' {
            $content = Get-Content -Path $Path -Raw
            $content = ConvertFrom-PodeFile -Content $content -Data $Data
        }

        default {
            if ($PodeSession.ViewEngine.Script -ne $null) {
                $content = Invoke-Command -ScriptBlock $PodeSession.ViewEngine.Script -ArgumentList $Path, $Data
            }
        }
    }

    Write-HtmlResponse -Value $content -NoConvert
}

# write data to tcp stream
function Write-ToTcpStream
{
    param (
        [Parameter()]
        [ValidateNotNull()]
        [string]
        $Message,

        [Parameter()]
        $Client
    )

    if ($Client -eq $null) {
        $Client = $PodeSession.Tcp.Client
    }

    $stream = $Client.GetStream()
    $encoder = New-Object System.Text.ASCIIEncoding
    $buffer = $encoder.GetBytes("$($Message)`r`n")
    $stream.Write($buffer, 0, $buffer.Length)
    $stream.Flush()
}

function Read-FromTcpStream
{
    param (
        [Parameter()]
        $Client
    )

    if ($Client -eq $null) {
        $Client = $PodeSession.Tcp.Client
    }

    $bytes = New-Object byte[] 8192
    $stream = $client.GetStream()
    $encoder = New-Object System.Text.ASCIIEncoding
    $bytesRead = $stream.Read($bytes, 0, 8192)
    $message = $encoder.GetString($bytes, 0, $bytesRead)
    return $message
}