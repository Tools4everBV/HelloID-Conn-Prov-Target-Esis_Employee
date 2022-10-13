$permissions = @(
    @{
        DisplayName    = "Dynamic Department"
        Identification = @{
            Reference = "DynamicDepartment"
        }
    }
)
Write-Output $permissions | ConvertTo-Json -Depth 10