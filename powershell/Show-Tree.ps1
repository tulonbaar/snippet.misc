function Show-Tree {
    param(
        [string]$Path = ".",
        [string]$Prefix = "",
        [switch]$ShowFiles = $true,
        [int]$MaxDepth = -1,
        [int]$CurrentDepth = 0
    )
    
    # Sprawdź czy osiągnięto maksymalną głębokość
    if ($MaxDepth -ne -1 -and $CurrentDepth -ge $MaxDepth) {
        return
    }
    
    # Pobierz wszystkie elementy w katalogu
    $items = Get-ChildItem -Path $Path -Force | Sort-Object { $_.PSIsContainer }, Name -Descending
    
    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]
        $isLast = ($i -eq $items.Count - 1)
        
        # Określ znak łącznika
        $connector = if ($isLast) { "└── " } else { "├── " }
        $extension = if ($isLast) { "    " } else { "│   " }
        
        # Wyświetl element
        if ($item.PSIsContainer) {
            Write-Host "$Prefix$connector$($item.Name)/" -ForegroundColor Cyan
            # Rekurencyjnie wyświetl zawartość katalogu
            Show-Tree -Path $item.FullName -Prefix "$Prefix$extension" -ShowFiles:$ShowFiles -MaxDepth $MaxDepth -CurrentDepth ($CurrentDepth + 1)
        }
        elseif ($ShowFiles) {
            Write-Host "$Prefix$connector$($item.Name)" -ForegroundColor Gray
        }
    }
}

# Przykłady użycia:
# Show-Tree                                    # Pokaż wszystko w bieżącym katalogu
# Show-Tree -Path "C:\Users"                   # Pokaż strukturę określonego katalogu
# Show-Tree -ShowFiles:$false                  # Pokaż tylko foldery
# Show-Tree -MaxDepth 2                        # Ogranicz głębokość do 2 poziomów
