#
# Creates DSVM (VM) from the given VHD image which is represented as BLOB URL with SAS Token
#
# Prerequisities:
# - storage account with access as blob contributor
# - storage account to have containers: ubuntu1804vhds and ubuntu2004vhds
# - AzCopy (v10)
# 

# expecting two parameters
# URL...from build pipeline, URL to blob (VHD) with SAS Token
# name...name of the image to be created, used also for RG name and Image name and VM name
# vmsize...default "Standard_B2s", other possible: Standard_NC6
# nologin...whether to explicitly login to azcopy
#
# example: .\create_dsvm_from_build.ps1 -name dsvm-ubuntu-1804-usi-2021 -url 
# example: .\create_dsvm_from_build.ps1 -url "https://STORAGE.blob.core.windows.net/ubuntu1804vhds/ACTUAL_BUILD_os.vhd?SAS_TOKEN" -name dsvm-ubuntu-1804-usi-20210802-new
#


param (
    [Parameter(Mandatory=$true)][string]$url, 
    [Parameter(Mandatory=$true)][alias("n")][string]$name,
    [alias("s")][string]$vmsize = "Standard_B2s", #Standard_NC6, Standard_NC6s_v3, Standard_NC4as_T4_v3
    [alias("os")][string]$ostype = "Ubuntu18", #Windows, Ubuntu20
    [switch]$nologin = $false,
    [switch]$onlybuild = $false
    )


###############################################################################
# VARIABLES:
# change to suit your environment
###############################################################################
$secrets = Get-Content config-secrets.json | ConvertFrom-Json
write-host "Secrets loaded."
$config = Get-Content config.json | ConvertFrom-Json
write-host "Configuration loaded."

$tenant_id = $secrets.tenant_id # MSFT Tenant
$subscription_id = $secrets.subscription_id
$admin_username = $secrets.adminuser
$admin_password = $secrets.pass
$inbound_ip_address = $secrets.inbound_ip_address # IP address for restriction firewall rules

$image_resource_group = $config.image_resource_group
$vm_region = $config.vm_region
$blob_storage_name = $config.blob_storage_name # name of the storage account where the VHD will be copied (it expects to have same containers as the original: ubuntu1804vhds or ubuntu2004vhds, etc.)

###############################################################################


if ($onlybuild) {
    Write-Host "Only buyilding the image - skipping logging..."
} else {
    if ($nologin) {
        Write-Host "Trying without login..."
    } 
    else {
        # # login into azopy, only when parameter is there
        # azcopy login --tenant-id $tenant_id
        
        # how you get the sec password
        # $secPassword = ConvertTo-SecureString -AsPlainText -Force -String '<our password here>'
        # $secPassword | ConvertFrom-SecureString | Out-File -FilePath C:\config-sp-secrets.txt
        ## Authenticate through service principal into Azure
        $azureAppCred = (New-Object System.Management.Automation.PSCredential $secrets.sp_app_id, ($secrets.sp_pass_sec | ConvertTo-SecureString))
        Connect-AzAccount -ServicePrincipal -SubscriptionId $secrets.subscription_id -TenantId $secrets.tenant_id -Credential $azureAppCred

        # quest-sp-pass-powershell
        $secret_sp_pass = Get-AzKeyVaultSecret -VaultName "quest-kv" -Name "quest-sp-pass-powershell" -AsPlainText

        $Env:AZCOPY_SPA_CLIENT_SECRET = $secret_sp_pass
        azcopy login --tenant-id $tenant_id --service-principal --application-id $secrets.sp_app_id

        Write-Host "Logged into AzCopy!"
    }
}


# $src = $url

# get the name  "xxx.vdh"
$img_tmp=$url.Split("?")[0]
# write-host "aaa: $img_tmp"
$img_name=$img_tmp.Split("/")[-1]

# get the OS, container loaction shoud be ubuntu1804vhds or ubuntu2004vhds, etc.
$img_tmp=$img_tmp.Split("/")[-2]
$img_os_name = $img_tmp

$supported_container_names = "ubuntu1804vhds", "ubuntu2004vhds","windows2019"
if ($supported_container_names.Contains($img_os_name))
{
    # create destination for AZCOPY
    $dest = "https://$blob_storage_name.blob.core.windows.net/$img_os_name/$img_name"
} 
else
{
    write-host "image is probably snapshot of $ostype"
    #TODO support other OS -> based on some variable
    if ("Windows" -eq $ostype) 
    {
        $img_os_name = "windows2019"
    }
    elseif ("Ubuntu18" -eq $ostype) {
        $img_os_name = "ubuntu1804vhds"
    } elseif ("Ubuntu20" -eq $ostype) {
        $img_os_name = "ubuntu2004vhds"
    }
    else {
        "Not supported ostype=$ostype."
        exit
    }
    $img_name = "$name.vhd"
    $dest = "https://$blob_storage_name.blob.core.windows.net/$img_os_name/$img_name"
}

#os-type mapping
if ("Windows" -eq $ostype) 
{
    $ostype = "Windows"
}
elseif ("Ubuntu18" -eq $ostype) {
    $ostype = "Linux"
} elseif ("Ubuntu20" -eq $ostype) {
    $ostype = "Linux"
}
else {
    "Not supported ostype=$ostype."
    exit
}

# debug output
write-host "VHD name: $img_name"
write-host "Blob Container: $img_os_name"

# write-host "DEST: $dest"
# exit
# create VM properties (name, rg, ...)
$rg_name = "Q-$name"
$vm_name = "Q-$name"
$img_URN = "/subscriptions/$subscription_id/resourceGroups/$image_resource_group/providers/Microsoft.Compute/images/$name"

write-host "Final Image Name: $name"
# write-host "rg $rg_name"
# write-host "vm $vm_name"
# write-host "URN $img_URN"


if ($onlybuild) {
    write-host "Skipping donwloading VHD (onlybuild:$onlybuild)"
} else {
    write-host "[CREATE-IMAGE-STAGE] Copying..."
    azcopy copy "$url" "$dest" --blob-type PageBlob
}

if( -not $? )
{
    "Encountered error during copy of VHD to Storage."
    exit
}

write-host "[CREATE-IMAGE-STAGE] Creating Image..."
az image create --resource-group Q-SharedImageGallery --hyper-v-generation V1 --location "$vm_region" --os-disk-caching ReadWrite --os-type $ostype --storage-sku  StandardSSD_LRS --zone-resilient false --source "$dest" --name $name 
if( -not $? )
{
    "Encountered error during Image creation."
    exit
}

write-host "[CREATE-IMAGE-STAGE] Creating VM ($vmsize)..."
az group create -l westeurope -n $rg_name
if( -not $? )
{
    "Couldn't create Resoure Group."
    exit
}
az vm create --size $vmsize -g $rg_name -n $vm_name --image $img_URN --admin-username $admin_username --admin-password $admin_password
if( -not $? )
{
    "Couldn/t create VM from the image."
    exit
}

# add firewall rules to accept only connection from certain IP addresses
$nsg_name = "${vm_name}NSG"
write-host "[UPDATE-FW-STAGE] Updating firewall rules on NSG: $nsg_name..."
az network nsg rule create -g $rg_name --nsg-name $nsg_name -n "Jupyter" --priority 1099 --source-address-prefixes $inbound_ip_address --destination-port-ranges 8000 --access Allow --protocol Tcp --description "Jupyter rule to Allow on 8000"
az network nsg rule update -g $rg_name --nsg-name $nsg_name -n "default-allow-ssh" --source-address-prefixes $inbound_ip_address

write-host "[CLEANUP-STAGE]"
# get details from VM
$vm = az vm show --resource-group $rg_name --name $vm_name -d --query [osProfile.computerName,resourceGroup,publicIps,powerState,osProfile.adminUsername] -o tsv

$vm_computerName=$vm[0]
$vm_resourceGroup=$vm[1]
$vm_publicIps=$vm[2]
# $vm_powerState=$vm[3]
$vm_adminUsername=$vm[4]

write-host ""
write-host "###############################################################################"
write-host "[CREATE-IMAGE-STAGE] VM Created..."
write-host "VM Name: $vm_computerName"
write-host "VM RG: $vm_resourceGroup"
write-host "VM IP: $vm_publicIps"
write-host "VM SSH: ssh $vm_adminUsername@$vm_publicIps"
write-host "Jupyter URL: https:/${vm_publicIps}:8000"
write-host "donwload inventory.xlsx: scp $vm_adminUsername@${vm_publicIps}:/dsvm/inventory/inventory.xlsx c:\\TMP\\PRJ\\_QUEST\\azure-dsvm-usi-test-invetories\\inventory-$vm_computerName.xlsx"
write-host "CHECK DETAILS: az vm show --name $vm_computerName --resource-group $vm_resourceGroup --show-details --subscription $subscription_id"
write-host "Delete RG: az group delete --name $vm_resourceGroup --no-wait --yes"
write-host "###############################################################################"
write-host "Done."
