#
# Creates DSVM (VM) from Market Place
#
# Prerequisities:
#   N/A

# expecting two parameters
# name...name of the image to be created, used also for RG name and Image name and VM name
# vmsize...default "Standard_B2s", other possible: Standard_NC6
# nologin...whether to explicitly login to azcopy
#
# example: .\create_dsvm_from_build.ps1 -name dsvm-ubuntu-1804-usi-2021 -url 
#

param (
    [Parameter(Mandatory=$true)][alias("n")][string]$name,
    [alias("s")][string]$vmsize = "Standard_B2s", #Standard_NC6, Standard_NC6s_v3, Standard_NC4as_T4_v3
    [alias("os")][string]$ostype = "Ubuntu18", #Windows, Ubuntu20
    [string]$version = "latest",
    [switch]$nologin = $false,
    [switch]$hidden = $false,
    [switch]$aml = $false # DSVM Attach to AML Workspace (currently  only firewall settings)
    )


###############################################################################
# VARIABLES:
# change to suit your environment
###############################################################################
$secrets = Get-Content config-secrets.json | ConvertFrom-Json
write-host "Secrets loaded."
$config = Get-Content config.json | ConvertFrom-Json
write-host "Configuration loaded."

$vm_region = $config.vm_region
$admin_username = $secrets.adminuser
$admin_password = $secrets.pass

$inbound_ip_address = $secrets.inbound_ip_address # IP address for restriction firewall rules
$image_publisher = $config.image_publisher # "microsoft-dsvm"
###############################################################################



if ("Windows" -eq $ostype)
{
    write-host "Windows image..."
    $image_offer = "dsvm-win-2019"
    $image_sku = "server-2019" 

    # # microsoft-dsvm:dsvm-windows:server-2019:19.12.12
    # $image_offer = "dsvm-windows"
    # $image_sku = "server-2019" 


    # OfferID - dsvmwindows-test
    # SKU - windows-test
    # version - 21.09.30
    if ($hidden) 
    {
        # TEST hidden OFFERING
        $image_offer = "dsvmwindows-test"
        $image_sku = "windows-test" 
    }
    
    # microsoft-dsvm:dsvm-win-2019:server-2019:21.05.22 

} elseif ("Ubuntu18" -eq $ostype) {
    
    write-host "$ostype image..."
    $image_offer = "ubuntu-1804"
    $image_sku = "1804"

} elseif ("Ubuntu20" -eq $ostype) {
    
    write-host "$ostype image..."
    $image_offer = "ubuntu-2004"
    $image_sku = "2004"
} else {
    "Not supported ostype=$ostype."
    exit
}

if ("latest" -eq $version)
{
    write-host "Trying to fetch latest version of sku: $image_sku | offer: $image_offer..."
    $image_list=$(az vm image list --publisher "microsoft-dsvm" --sku $image_sku --offer $image_offer --all --query "[?sku=='$image_sku'].version" -o tsv)
    
    foreach ($item in $image_list) {
        Write-Host "sku: $image_sku | offer: $image_offer | version: $item"
    }
    $latest_version =  $item
    write-host "Detected latest version ($latest_version) of sku: $image_sku | offer: $image_offer."
} else {
    # $latest_version = "21.09.13"
    # $latest_version = "21.09.20"
    $latest_version = $version
    write-host "Using (manual) latest version ($latest_version)"
}


# create VM properties (name, rg, ...)
$suffix = $latest_version.replace(".","")
$rg_name = "Q-$name-$suffix"
$vm_name = "Q-$name-$suffix"
$img_URN = $image_publisher + ":" + $image_offer + ":" + $image_sku + ":" + $latest_version
write-host "Image URN: $img_URN"

if ($PSBoundParameters.Debug -eq $true) {
    Write-Host "DEBUG MODE"
    exit
}

write-host "[CREATE-IMAGE-STAGE] Creating $ostype VM ($vmsize)..."
az group create -l $vm_region -n $rg_name
if( -not $? )
{
    "Couldn't create Resoure Group."
    exit
}

write-host "az vm create --size $vmsize -g $rg_name -n $vm_name --image $img_URN --admin-username myuser --admin-password ********"

az vm create --size $vmsize -g $rg_name -n $vm_name --image $img_URN --admin-username $admin_username --admin-password $admin_password
# az vm create --image 'microsoft-dsvm:ubuntu-2004:2004:21.08.30' --admin-username 'username' --admin-password 'enter password' --location 'eastus'

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
write-host "[CREATE-IMAGE-STAGE] $ostype VM Created..."
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


