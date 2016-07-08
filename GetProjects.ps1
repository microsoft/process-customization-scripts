################################################################################################################
#
# gets a list of projects from an account and builds a csv of project names
#
# example: .\getprojects.ps1 "accountname.visualstudio.com" "PAT"
#        
#.\ConformProject.ps1 "https://wierman.visualstudio.com/DefaultCollection" "MCS Dynamics TFS" "D:\GIT Repos\My Daily Work\WIT Work\wierman.visualstudio.com\Projects\Process Template\MCS ERP Process" -ValidateOnly
################################################################################################################


param
(
    [Parameter(Mandatory=$true,HelpMessage="team services account is required. Usage Example: accountname.visualstudio.com")] [string] $account,
    [Parameter(Mandatory=$true,HelpMessage="access token is required.")] [string] $token   
)

$username = "";
 
$accessToken = ("{0}:{1}" -f $username,$token);
$accessToken = [System.Text.Encoding]::UTF8.GetBytes($accessToken);
$accessToken = [System.Convert]::ToBase64String($accessToken);
$headers = @{Authorization=("Basic {0}" -f $accessToken)};
$instance = "danhellem";

Write-Host "Getting list of projects from $account" -ForegroundColor Yellow    
$projects = Invoke-RestMethod -Uri "https://$($account)/DefaultCollection/_apis/projects?api-version=1.0" -Headers $headers -Method Get
$OutArray = @(); 

Write-Host "Building array of projects..." -ForegroundColor Yellow   

foreach($project in $projects.value)
{
    $OutArray += New-Object PsObject -Property @{ 
        'Project' = $project.name        
    } 
    
    Write-Host $project.name | ft
}

Write-Host "Exporting to csv" -ForegroundColor Yellow   
$OutArray | Export-Csv "final.csv" -NoTypeInformation

Write-Host "Done" -ForegroundColor Green
