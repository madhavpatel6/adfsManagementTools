Function Test-CertificateAvailable
{
    param(
        $adfsCertificate, # Single element of list Generated by Get-AdfsCertificatesToTest
        [string]
        $certificateType,
        [bool]
        $isPrimary = $true,
        [string]
        $notRunReason
    )

    $testName = Create-CertCheckName -certType $certificateType -checkName "NotFoundInStore" -isPrimary $isPrimary

    if (-not $adfsCertificate -and [String]::IsNullOrEmpty($notRunReason))
    {
        $notRunReason = "Certificate object is null."
    }

    if (-not [String]::IsNullOrEmpty($notRunReason))
    {
        return Create-CertificateCheckResult -cert $null -testName $testName -result NotRun -detail $notRunReason
    }

    try
    {
        $thumbprint = $adfsCertificate.Thumbprint
        $testResult = New-Object TestResult -ArgumentList($testName)
        $testResult.Result = [ResultType]::NotRun;
        $testResult.Output = @{$tpKey = $thumbprint}

        if ($adfsCertificate.StoreLocation -eq "LocalMachine")
        {
            $certStore = New-Object System.Security.Cryptography.X509Certificates.X509Store($adfsCertificate.StoreName, `
                    [System.Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
            try
            {
                $certStore.Open("IncludeArchived")

                $certSearchResult = $certStore.Certificates | where {$_.Thumbprint -eq $thumbprint}
                if (($certSearchResult | measure).Count -eq 0)
                {
                    $testResult.Detail = "$certificateType certificate with thumbprint $thumbprint not found in LocalMachine\{0} store.`n" -f $adfsCertificate.StoreName
                    $testResult.Result = [ResultType]::Fail
                }
                else
                {
                    $testResult.Result = [ResultType]::Pass
                }
            }
            catch
            {
                $testResult.Result = [ResultType]:: NotRun;
                $testResult.Detail = "$certificateType certificate with thumbprint $thumbprint encountered exception with message`n" + $_.Exception.Message
            }
            finally
            {
                $certStore.Close()
            }
        }
        else
        {
            $testResult.Result = [ResultType]:: NotRun;
            $testResult.Detail = "$certificateType certificate with thumbprint $thumbprint not checked for availability because it is in store: " + $adfsCertificate.StoreLocation
        }

        return $testResult
    }
    catch [Exception]
    {
        return Create-ErrorExceptionTestResult $testName $_.Exception
    }
}

function Test-CertificateExpired
{
    param (
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
        $cert,
        [string]
        $certificateType,
        [bool]
        $isPrimary = $true,
        [string]
        $notRunReason
    )

    $checkName = "Expired"

    $testName = Create-CertCheckName -certType $certificateType -checkName $checkName -isPrimary $isPrimary

    if (-not $cert -and [String]::IsNullOrEmpty($notRunReason))
    {
        $notRunReason = "Certificate object is null."
    }
    if (-not [String]::IsNullOrEmpty($notRunReason))
    {
        return Create-CertificateCheckResult -cert $null -testName $testName -result NotRun -detail $notRunReason
    }

    try
    {
        if (Verify-IsCertExpired -cert $cert)
        {
            $tp = $cert.Thumbprint

            $certificateExpiredTestDetail = "$certificateType certificate with thumbprint $tp has expired.`n";
            $certificateExpiredTestDetail += "Valid From: " + $cert.NotBefore.ToString() + "`nValid To: " + $cert.NotAfter.ToString();
            $certificateExpiredTestDetail += "`nAutoCertificateRollover Enabled: " + (Retrieve-AdfsProperties).AutoCertificateRollover + "`n";
            return Create-CertificateCheckResult -cert $cert -testName $testName -result Fail -detail $certificateExpiredTestDetail
        }
        else
        {
            return Create-CertificateCheckResult -cert $cert -testName $testName -result Pass
        }
    }
    catch [Exception]
    {
        return Create-ErrorExceptionTestResult $testName $_.Exception
    }
}

function Test-CertificateAboutToExpire
{

    param (
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
        $cert,
        [string]
        $certificateType,
        [bool]
        $isPrimary = $true,
        [string]
        $notRunReason
    )
    $checkName = "AboutToExpire"

    $testName = Create-CertCheckName -certType $certificateType -checkName $checkName -isPrimary $isPrimary

    $expiryLimitInDays = 90;

    if (-not $cert -and [String]::IsNullOrEmpty($notRunReason))
    {
        $notRunReason = "Certificate object is null."
    }
    if (-not [String]::IsNullOrEmpty($notRunReason))
    {
        return Create-CertificateCheckResult -cert $null -testName $testName -result NotRun -detail $notRunReason
    }

    try
    {
        $properties = Retrieve-AdfsProperties
        if ($properties.AutoCertificateRollover -and ($certificateType -eq "Token-Decrypting" -or $certificateType -eq "Token-Signing"))
        {
            return Create-CertificateCheckResult -cert $cert -testName $testName -result NotRun -detail "Check Skipped when AutoCertificateRollover is enabled"
        }

        $expirtyMinusToday = [System.Convert]::ToInt32(($cert.NotAfter - (Get-Date)).TotalDays);
        if ($expirtyMinusToday -le $expiryLimitInDays)
        {
            $tp = $cert.Thumbprint

            $certificateAboutToExpireTestDetail = "$certificateType certificate with thumbprint $tp is about to expire in $expirtyMinusToday days.`n"
            $certificateAboutToExpireTestDetail += "Valid From: " + $cert.NotBefore.ToString() + "`nValid To: " + $cert.NotAfter.ToString();
            $certificateAboutToExpireTestDetail += "`nAutoCertificateRollover Enabled: " + (Retrieve-AdfsProperties).AutoCertificateRollover + "`n";
            return Create-CertificateCheckResult -cert $cert -testName $testName -result Fail -detail $certificateAboutToExpireTestDetail
        }
        else
        {
            return Create-CertificateCheckResult -cert $cert -testName $testName -result Pass
        }
    }
    catch [Exception]
    {
        return Create-ErrorExceptionTestResult $testName $_.Exception
    }
}

function Test-CertificateHasPrivateKey
{
    param (
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
        $cert,
        [string]
        $certificateType,
        [bool]
        $isPrimary = $true,
        [string]
        $storeName,
        [string]
        $storeLocation,
        [string]
        $notRunReason
    )

    $checkName = "PrivateKeyAbsent"

    $testName = Create-CertCheckName -certType $certificateType -checkName $checkName -isPrimary $isPrimary

    if (-not $cert -and [String]::IsNullOrEmpty($notRunReason))
    {
        $notRunReason = "Certificate object is null."
    }

    if (-not [String]::IsNullOrEmpty($notRunReason))
    {
        return Create-CertificateCheckResult -cert $null -testName $testName -result NotRun -detail $notRunReason
    }

    try
    {
        $properties = Retrieve-AdfsProperties
        if ($properties.AutoCertificateRollover -and ($certificateType -eq "Token-Decrypting" -or $certificateType -eq "Token-Signing"))
        {
            return Create-CertificateCheckResult -cert $cert -testName $testName -result NotRun -detail "Check Skipped when AutoCertificateRollover is enabled"
        }

        #special consideration to the corner case where auto certificate rollover was on, then turned off, leaving behind some certificates in the CU\MY store
        #in which case, we cannot ascertain whether the private key is present or not
        if ($storeLocation -eq "CurrentUser")
        {
            return Create-CertificateCheckResult -cert $cert -testName $testName -result NotRun -detail "Check Skipped because the certificate is in the CU\MY store"
        }

        if ($cert.HasPrivateKey)
        {
            return Create-CertificateCheckResult -cert $cert -testName $testName -result Pass
        }
        else
        {
            $tp = $cert.Thumbprint
            $detail = "$certificateType certificate with thumbprint $tp does not have a private key."
            return Create-CertificateCheckResult -cert $cert -testName $testName -result Fail -detail $detail
        }
    }
    catch [Exception]
    {
        return Create-ErrorExceptionTestResult $testName $_.Exception
    }
}

function Test-CertificateSelfSigned
{
    param (
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
        $cert,
        [string]
        $certificateType,
        [bool]
        $isPrimary = $false,
        [string]
        $notRunReason
    )

    $checkName = "IsSelfSigned"

    $testName = Create-CertCheckName -certType $certificateType -checkName $checkName -isPrimary $isPrimary

    if (-not $cert -and [String]::IsNullOrEmpty($notRunReason))
    {
        $notRunReason = "Certificate object is null."
    }

    if (-not [String]::IsNullOrEmpty($notRunReason))
    {
        return Create-CertificateCheckResult -cert $null -testName $testName -result NotRun -detail $notRunReason
    }

    try
    {
        $properties = Retrieve-AdfsProperties
        if ($properties.AutoCertificateRollover -and ($certificateType -eq "Token-Decrypting" -or $certificateType -eq "Token-Signing"))
        {
            return Create-CertificateCheckResult -cert $cert -testName $testName -result NotRun -detail "Check Skipped when AutoCertificateRollover is enabled"
        }
        if (Verify-IsCertSelfSigned $cert)
        {
            $tp = $cert.Thumbprint
            $detail = "$certificateType certificate with thumbprint $tp is self-signed."
            return Create-CertificateCheckResult -cert $cert -testName $testName -result Fail -detail $detail
        }
        else
        {
            return Create-CertificateCheckResult -cert $cert -testName $testName -result Pass
        }
    }
    catch [Exception]
    {
        return Create-ErrorExceptionTestResult $testName $_.Exception
    }
}

function Test-CertificateCRL
{
    param (
        [System.Security.Cryptography.X509Certificates.X509Certificate2]
        $cert,
        [string]
        $certificateType,
        [bool]
        $isPrimary = $false,
        [string]
        $notRunReason
    )

    $checkName = "Revoked"
    $chainStatusKey = "ChainStatus"

    $testName = Create-CertCheckName -certType $certificateType -checkName $checkName -isPrimary $isPrimary

    if (-not $cert -and [String]::IsNullOrEmpty($notRunReason))
    {
        $notRunReason = "Certificate object is null."
    }

    if (-not [String]::IsNullOrEmpty($notRunReason))
    {
        return Create-CertificateCheckResult -cert $null -testName $testName -result NotRun -detail $notRunReason
    }

    try
    {
        $crlResult = VerifyCertificateCRL -cert $cert
        $passFail = [ResultType]::Pass
        if (($crlResult.ChainBuildResult -eq $false) -and ($crlResult.IsSelfSigned -eq $false))
        {
            $passFail = [ResultType]::Fail
        }
        $testResult = Create-CertificateCheckResult -cert $cert -testName $testName -result $passFail
        $testDetail = "Thumbprint: " + $crlResult.Thumbprint + "`n"

        $testResult.Output.Add($chainStatusKey, "NONE")
        if ($crlResult.ChainStatus)
        {
            $testResult.Output.Set_Item($chainStatusKey, $crlResult.ChainStatus)
            foreach ($chainStatus in $crlResult.ChainStatus)
            {
                $testDetail = $testDetail + $chainStatus.Status + "-" + $chainStatus.StatusInformation + [System.Environment]::NewLine
            }
        }

        $testResult.Detail = $testDetail
        return $testResult
    }
    catch [Exception]
    {
        return Create-ErrorExceptionTestResult $testName $_.Exception
    }
}