$script:sqlServerDscHelperModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Modules\SqlServerDsc.Common'
$script:resourceHelperModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\Modules\DscResource.Common'

Import-Module -Name $script:sqlServerDscHelperModulePath
Import-Module -Name $script:resourceHelperModulePath

$script:localizedData = Get-LocalizedData -DefaultUICulture 'en-US'

<#
    .SYNOPSIS
        Gets the current value of a SQL configuration option.

    .PARAMETER ServerName
        Hostname of the SQL Server to be configured. Default value is the current
        computer name.

    .PARAMETER InstanceName
        Name of the SQL instance to be configured. Default is 'MSSQLSERVER'.

    .PARAMETER OptionName
        The name of the SQL configuration option to be checked.

    .PARAMETER OptionValue
        The desired value of the SQL configuration option.

    .PARAMETER RestartService
        *** Not used in this function ***
        Determines whether the instance should be restarted after updating the
        configuration option.

    .PARAMETER RestartTimeout
        *** Not used in this function ***
        The length of time, in seconds, to wait for the service to restart. Default
        is 120 seconds.

    .PARAMETER ProcessOnlyOnActiveNode
        *** Not used in this function ***
        Specifies that the resource will only determine if a change is needed if the target node is the active host of the SQL Server Instance.
        Not used in Set-TargetResource.
#>
function Get-TargetResource
{
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServerName = (Get-ComputerName),

        [Parameter(Mandatory = $true)]
        [System.String]
        $InstanceName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OptionName,

        [Parameter(Mandatory = $true)]
        [System.Int32]
        $OptionValue,

        [Parameter()]
        [System.Boolean]
        $RestartService = $false,

        [Parameter()]
        [System.UInt32]
        $RestartTimeout = 120,

        [Parameter()]
        [System.UInt32]
        $ProcessOnlyOnActiveNode = 120
    )

    $sql = Connect-SQL -ServerName $ServerName -InstanceName $InstanceName -ErrorAction 'Stop'

    # Is this node actively hosting the SQL instance?
    $isActiveNode = Test-ActiveNode -ServerObject $sql

    # Get the current value of the configuration option.
    $option = $sql.Configuration.Properties |
        Where-Object -FilterScript { $_.DisplayName -eq $OptionName }

    if (-not $option)
    {
        $errorMessage = $script:localizedData.ConfigurationOptionNotFound -f $OptionName
        New-InvalidArgumentException -ArgumentName 'OptionName' -Message $errorMessage
    }

    Write-Verbose -Message (
        $script:localizedData.CurrentOptionValue `
            -f $OptionName, $option.ConfigValue
    )

    return @{
        ServerName     = $ServerName
        InstanceName   = $InstanceName
        OptionName     = $option.DisplayName
        OptionValue    = $option.ConfigValue
        RestartService = $RestartService
        RestartTimeout = $RestartTimeout
        IsActiveNode   = $isActiveNode
    }
}

<#
    .SYNOPSIS
        Sets the value of a SQL configuration option.

    .PARAMETER ServerName
        Hostname of the SQL Server to be configured. Default value is the current
        computer name.

    .PARAMETER InstanceName
        Name of the SQL instance to be configured. Default is 'MSSQLSERVER'.

    .PARAMETER OptionName
        The name of the SQL configuration option to be set.

    .PARAMETER OptionValue
        The desired value of the SQL configuration option.

    .PARAMETER RestartService
        Determines whether the instance should be restarted after updating the
        configuration option.

    .PARAMETER RestartTimeout
        The length of time, in seconds, to wait for the service to restart. Default
        is 120 seconds.

    .PARAMETER ProcessOnlyOnActiveNode
        *** Not used in this function ***
        Specifies that the resource will only determine if a change is needed if the target node is the active host of the SQL Server Instance.
        Not used in Set-TargetResource.
#>
function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServerName = (Get-ComputerName),

        [Parameter(Mandatory = $true)]
        [System.String]
        $InstanceName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OptionName,

        [Parameter(Mandatory = $true)]
        [System.Int32]
        $OptionValue,

        [Parameter()]
        [System.Boolean]
        $RestartService = $false,

        [Parameter()]
        [System.UInt32]
        $RestartTimeout = 120,

        [Parameter()]
        [System.Boolean]
        $ProcessOnlyOnActiveNode
    )

    $sql = Connect-SQL -ServerName $ServerName -InstanceName $InstanceName -ErrorAction 'Stop'

    # Get the current value of the configuration option.
    $option = $sql.Configuration.Properties |
        Where-Object -FilterScript { $_.DisplayName -eq $OptionName }

    if (-not $option)
    {
        $errorMessage = $script:localizedData.ConfigurationOptionNotFound -f $OptionName
        New-InvalidArgumentException -ArgumentName 'OptionName' -Message $errorMessage
    }

    $option.ConfigValue = $OptionValue
    $sql.Configuration.Alter()

    Write-Verbose -Message (
        $script:localizedData.ConfigurationValueUpdated `
            -f $OptionName, $OptionValue
    )

    if ($option.IsDynamic -eq $true)
    {
        Write-Verbose -Message $script:localizedData.NoRestartNeeded
    }
    elseif (($option.IsDynamic -eq $false) -and ($RestartService -eq $true))
    {
        Write-Verbose -Message (
            $script:localizedData.AutomaticRestart `
                -f $ServerName, $InstanceName
        )

        Restart-SqlService -ServerName $ServerName -InstanceName $InstanceName -Timeout $RestartTimeout
    }
    else
    {
        Write-Warning -Message (
            $script:localizedData.ConfigurationRestartRequired `
                -f $OptionName, $OptionValue, $ServerName, $InstanceName
        )
    }
}

<#
    .SYNOPSIS
        Determines whether a SQL configuration option value is properly set.

    .PARAMETER ServerName
        Hostname of the SQL Server to be configured. Default value is the current
        computer name.

    .PARAMETER InstanceName
        Name of the SQL instance to be configured. Default is 'MSSQLSERVER'.

    .PARAMETER OptionName
        The name of the SQL configuration option to be tested.

    .PARAMETER OptionValue
        The desired value of the SQL configuration option.

    .PARAMETER RestartService
        *** Not used in this function ***
        Determines whether the instance should be restarted after updating the
        configuration option.

    .PARAMETER RestartTimeout
        *** Not used in this function ***
        The length of time, in seconds, to wait for the service to restart. Default
        is 120 seconds.


    .PARAMETER ProcessOnlyOnActiveNode
        Specifies that the resource will only determine if a change is needed if
        the target node is the active host of the SQL Server instance.
#>
function Test-TargetResource
{
    [System.Diagnostics.CodeAnalysis.SuppressMessageAttribute('SqlServerDsc.AnalyzerRules\Measure-CommandsNeededToLoadSMO', '', Justification='The command Connect-Sql is called when Get-TargetResource is called')]
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ServerName = (Get-ComputerName),

        [Parameter(Mandatory = $true)]
        [System.String]
        $InstanceName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $OptionName,

        [Parameter(Mandatory = $true)]
        [System.Int32]
        $OptionValue,

        [Parameter()]
        [System.Boolean]
        $RestartService = $false,

        [Parameter()]
        [System.UInt32]
        $RestartTimeout = 120,

        [Parameter()]
        [System.Boolean]
        $ProcessOnlyOnActiveNode
    )

    # Get the current value of the configuration option.
    $getTargetResourceResult = Get-TargetResource @PSBoundParameters


    <#
        If this is supposed to process only the active node, and this is not the
        active node, don't bother evaluating the test.
    #>
    if ($ProcessOnlyOnActiveNode -and -not $getTargetResourceResult.IsActiveNode)
    {
        Write-Verbose -Message (
            $script:localizedData.NotActiveNode -f (Get-ComputerName), $InstanceName
        )

        return $result
    }

    if ($getTargetResourceResult.OptionValue -eq $OptionValue)
    {
        Write-Verbose -Message (
            $script:localizedData.InDesiredState `
                -f $OptionName
        )

        $result = $true
    }
    else
    {
        Write-Verbose -Message (
            $script:localizedData.NotInDesiredState `
                -f $OptionName, $OptionValue, $getTargetResourceResult.OptionValue
        )

        $result = $false
    }

    return $result
}
