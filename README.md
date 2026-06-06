# 🔐 Install-vCenterSSL

**Automated SSL Certificate Installation for VMware vCenter using Let's Encrypt**

[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%2B%20%7C%207.x-blue)](https://github.com/PowerShell/PowerShell)
[![vCenter](https://img.shields.io/badge/vCenter-7.x%20%7C%208.x-green)](https://www.vmware.com/products/vcenter)
[![License](https://img.shields.io/badge/license-MIT-red)](LICENSE)

---

## 📋 Overview

**Install-vCenterSSL** is a powerful PowerShell automation script that streamlines the process of installing **free, trusted SSL/TLS certificates** on VMware vCenter Server. 

The script leverages:
- 🎯 **Let's Encrypt** (via Posh-ACME) for certificate generation
- ✅ **Automated validation** with MD5/SHA256 hash verification
- 🔄 **ACME protocol** for certificate request management
- 🛡️ **ISRG Root X1** certificate chain for complete trust

### Key Benefits

| Feature | Benefit |
|---------|---------|
| **Free Certificates** | No licensing costs, 90-day renewal cycle |
| **Fully Automated** | Minimal manual intervention required |
| **Secure by Default** | Certificate validation & hash verification |
| **Production Ready** | Tested on vCenter 7.x and 8.x |
| **Robust Error Handling** | Detailed logging and retry logic |
| **Cross-Platform** | Works on PowerShell 5.1 and 7.x (Core) |

---

## 🚀 Quick Start

### Prerequisites

- **PowerShell** 5.1 or higher (or PowerShell 7.x Core)
- **vCenter Server** 7.x or 8.x
- **Network Access** to vCenter (HTTPS port 443)
- **Internet Access** for Let's Encrypt API and module downloads
- **Administrator Credentials** for vCenter

### Basic Usage

```powershell
# Run the script with required parameters
.\Install-vCenterSSL.ps1 `
  -vCenterURL 'vc.example.com' `
  -CommonName 'vc.example.com' `
  -EmailContact 'admin@example.com'
```

### With Credentials Parameter

```powershell
# Pre-supply vCenter credentials
$credential = Get-Credential
.\Install-vCenterSSL.ps1 `
  -vCenterURL 'vc.example.com' `
  -CommonName 'vc.example.com' `
  -EmailContact 'admin@example.com' `
  -vCenterCredential $credential `
  -SkipCertificateValidation
```

---

## 📖 Parameters

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `vCenterURL` | String | ✅ Yes | FQDN or IP address of vCenter Server (e.g., `vc.example.com`) |
| `CommonName` | String | ✅ Yes | Certificate Common Name (CN) - typically the vCenter FQDN |
| `EmailContact` | String | ✅ Yes | Email address for ACME account & renewal notifications |
| `vCenterCredential` | PSCredential | ❌ No | vCenter administrator credentials (prompted if not provided) |
| `LogPath` | String | ❌ No | Directory for script logs. Default: `~/Documents/vCenterSSL_Logs` |
| `SkipCertificateValidation` | Switch | ❌ No | Skip SSL certificate validation (useful for self-signed certs) |
| `MaxRetries` | Integer | ❌ No | Max retry attempts for API calls. Default: `3` |

---

## 🔄 Workflow Overview

The script executes in **8 phases**:

### Phase 1️⃣: Pre-Flight Checks
- ✓ DNS resolution validation
- ✓ vCenter connectivity test (HTTPS port 443)

### Phase 2️⃣: Module Setup
- ✓ Execution policy configuration
- ✓ Posh-ACME module installation (if missing)
- ✓ Module import and validation

### Phase 3️⃣: ACME Configuration
- ✓ Let's Encrypt server setup
- ✓ ACME account creation/verification
- ✓ Email contact association

### Phase 4️⃣: Certificate Management
- ✓ Check for existing valid certificates
- ✓ Option to reuse or request new certificate
- ✓ New certificate request to Let's Encrypt

### Phase 5️⃣: Root CA Validation
- ✓ Download ISRG Root X1 certificate
- ✓ SHA256 hash verification for security
- ✓ Complete certificate chain assembly

### Phase 6️⃣: Load Certificate Files
- ✓ Extract full chain from Posh-ACME storage
- ✓ Read private key file
- ✓ Prepare chain certificate

### Phase 7️⃣: Certificate Formatting
- ✓ Convert to PEM standard format
- ✓ Format certificate headers/footers
- ✓ Prepare JSON payload

### Phase 8️⃣: vCenter Installation
- ✓ Authenticate with vCenter REST API
- ✓ Upload certificate via API
- ✓ Confirm installation (HTTP 204 response)

---

## 📋 Example Scenarios

### Scenario 1: Automated Installation (No Prompts)

```powershell
# Pre-supply all credentials and configurations
$credential = Get-Credential
.\Install-vCenterSSL.ps1 `
  -vCenterURL 'vc.contoso.com' `
  -CommonName 'vc.contoso.com' `
  -EmailContact 'vcenter-admin@contoso.com' `
  -vCenterCredential $credential
```

### Scenario 2: Initial Setup with Self-Signed Cert

```powershell
# vCenter currently has self-signed certificate
.\Install-vCenterSSL.ps1 `
  -vCenterURL '192.168.1.100' `
  -CommonName 'vc.contoso.com' `
  -EmailContact 'admin@contoso.com' `
  -SkipCertificateValidation
```

### Scenario 3: Custom Log Directory

```powershell
# Store logs in custom location
.\Install-vCenterSSL.ps1 `
  -vCenterURL 'vc.example.com' `
  -CommonName 'vc.example.com' `
  -EmailContact 'admin@example.com' `
  -LogPath 'C:\Scripts\vCenter_Logs'
```

### Scenario 4: Aggressive Retry Configuration

```powershell
# Network is unreliable, increase retry attempts
.\Install-vCenterSSL.ps1 `
  -vCenterURL 'vc.example.com' `
  -CommonName 'vc.example.com' `
  -EmailContact 'admin@example.com' `
  -MaxRetries 5
```

---

## 🔒 Security Features

### Certificate Validation
```
✓ ISRG Root X1 certificate SHA256 hash verification
✓ Let's Encrypt trusted certificate chain
✓ 90-day certificate validity period
```

### Authentication
```
✓ Base64-encoded HTTP Basic Auth
✓ vCenter session token management
✓ Secure credential handling
```

### Error Handling
```
✓ Try-catch error management
✓ Retry logic with exponential backoff
✓ Detailed error logging and reporting
```

---

## 📊 Logging

All operations are logged to timestamped log files in the specified log directory.

**Log Location:** `~/Documents/vCenterSSL_Logs/vCenterSSL_YYYYMMDD_HHMMSS.log`

**Log Format:**
```
[2026-06-06 14:30:45] [INFO] Validating DNS resolution for: vc.example.com
[2026-06-06 14:30:46] [SUCCESS] DNS resolution successful: vc.example.com -> 192.168.1.100
[2026-06-06 14:30:47] [INFO] Authenticating with vCenter: vc.example.com
[2026-06-06 14:30:48] [SUCCESS] vCenter authentication successful
```

### Log Levels
- `INFO` - General information messages
- `SUCCESS` - Successful operation completion
- `WARN` - Warning messages (non-fatal)
- `ERROR` - Error messages (may be fatal)
- `DEBUG` - Debug-level diagnostic information

---

## 🛠️ Requirements

### Module Dependencies
- **Posh-ACME** (automatically installed if missing)

### System Requirements
- **Windows 10/11** or **Windows Server 2016+**
- **PowerShell 5.1** minimum (or PowerShell Core 7.x)
- **Internet connectivity** (for Let's Encrypt API)
- **vCenter Server 7.x or 8.x**

### Network Requirements
```
vCenter Machine → Let's Encrypt API (api.letsencrypt.org:443)
vCenter Machine → ISRG Root CA (letsencrypt.org:443)
Your Machine → vCenter (vcenter-server:443)
```

---

## ⚠️ Important Notes

### Before Running
1. **Backup existing certificate** from vCenter
2. **Test in non-production** environment first
3. **Ensure DNS is properly configured** for the vCenter FQDN
4. **Plan for service restart** - vCenter services will restart after installation

### After Running
1. **Verify certificate installation** in vCenter UI
2. **Clear browser cache** and verify SSL in web console
3. **Check certificate details** to confirm validity period
4. **Set up renewal process** for 90-day certificates (consider automation)

### Troubleshooting
- **DNS Resolution Fails:** Verify DNS settings and network connectivity
- **vCenter Authentication Failed:** Check username/password and RBAC permissions
- **Module Installation Fails:** Run PowerShell as Administrator
- **Certificate Hash Mismatch:** Network issue or MITM attack - investigate immediately

---

## 📝 Examples with Expected Output

```powershell
PS> .\Install-vCenterSSL.ps1 -vCenterURL 'vc.contoso.com' -CommonName 'vc.contoso.com' -EmailContact 'admin@contoso.com'

[2026-06-06 14:30:45] [INFO] Logging initialized at: C:\Users\Admin\Documents\vCenterSSL_Logs\vCenterSSL_20260606_143045.log
[2026-06-06 14:30:46] [INFO] Starting vCenter SSL Installation Workflow
[2026-06-06 14:30:46] [INFO] === Phase 1: Pre-Flight Checks ===
[2026-06-06 14:30:47] [SUCCESS] DNS resolution successful: vc.contoso.com -> 192.168.1.100
[2026-06-06 14:30:48] [SUCCESS] vCenter connectivity test passed
[2026-06-06 14:30:48] [INFO] === Phase 2: Module Setup ===
[2026-06-06 14:30:52] [SUCCESS] Posh-ACME module found (Version: 4.19.0)
[2026-06-06 14:30:53] [SUCCESS] Posh-ACME module imported successfully
...
[2026-06-06 14:31:15] [SUCCESS] === Installation Complete ===
[2026-06-06 14:31:15] [SUCCESS] Certificate for 'vc.contoso.com' successfully installed on vCenter

Success   : True
Message   : Certificate installation completed successfully
LogFile   : C:\Users\Admin\Documents\vCenterSSL_Logs\vCenterSSL_20260606_143045.log
Timestamp : 6/6/2026 2:31:15 PM
```

---

## 🔄 Certificate Renewal

Let's Encrypt certificates are valid for **90 days**. For automatic renewal:

### Option 1: Schedule PowerShell Task
```powershell
# Create a scheduled task to run the renewal script
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-NoProfile -ExecutionPolicy Bypass -File 'C:\Scripts\Install-vCenterSSL.ps1' -vCenterURL 'vc.example.com' -CommonName 'vc.example.com' -EmailContact 'admin@example.com'"
$trigger = New-ScheduledTaskTrigger -DaysInterval 60 -At 2:00AM
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "vCenter SSL Renewal"
```

### Option 2: Use Posh-ACME Renewal
```powershell
# Check certificate status
Get-PACertificate -MainDomain 'vc.example.com'

# Manually renew if needed
Submit-Renewal
```

---

## 📚 Related Links

- **Posh-ACME Documentation:** https://github.com/rmbolger/Posh-ACME
- **Let's Encrypt:** https://letsencrypt.org
- **VMware vCenter REST API:** https://developer.vmware.com/apis/vcenter/
- **Original Repository:** https://github.com/virtuallywired/Install-vCenterSSL

---

## 📄 License

This project is licensed under the **MIT License** - see the [LICENSE](LICENSE) file for details.

---

## 🤝 Contributing

Contributions are welcome! Please feel free to:
- Report bugs and issues
- Suggest improvements and features
- Submit pull requests

---

## 👨‍💻 Authors

- **Original Author:** Nicholas Mangraviti ([virtuallywired.io](https://virtuallywired.io))
- **Refactored & Optimized:** 2026

---

## ❓ FAQ

**Q: Is this script safe to run in production?**  
A: Yes, but test in a non-production environment first. The script has extensive error handling and logging.

**Q: Can I use wildcards in the CommonName?**  
A: The current implementation uses a single CN. For wildcard or multi-domain certificates, modify the `New-ACMECertificate` function.

**Q: What happens after installation?**  
A: vCenter services automatically restart to load the new certificate. Plan accordingly.

**Q: Can I reuse an existing certificate?**  
A: Yes, the script checks for valid existing certificates and offers to reuse them.

**Q: How do I update vCenter if the certificate expires?**  
A: Re-run the script. It will request a renewal certificate from Let's Encrypt.

---

## 🐛 Support & Issues

If you encounter issues, please:
1. Check the log file in `~/Documents/vCenterSSL_Logs/`
2. Verify all parameters are correct
3. Test network connectivity to vCenter
4. Create a GitHub issue with log details

---

**Made with ❤️ for VMware vCenter administrators**
