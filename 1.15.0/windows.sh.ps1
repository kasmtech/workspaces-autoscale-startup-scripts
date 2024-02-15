#ps1_sysnative

$pass = ConvertTo-SecureString -String {connection_password} -AsPlainText -Force

New-LocalUser -Name {connection_username} -Description 'Programatically generated Kasm user account' -Password $pass -PasswordNeverExpires -AccountNeverExpires | Add-LocalGroupMember -Group administrators | Add-LocalGroupMember -Group "Remote Desktop Users"

Start-Service -Name "Audiosrv"