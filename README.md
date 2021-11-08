# azure-dsvm-testing
A DSVM test kit mainly for creating DSVM images from either Image build process or Azure Marketplace.

## Creating image

**From Azure Marketplace**

```powershell
.\create_marketplace_dsvm.ps1 -n this-is-my-vm-name
```
parameters:
* name...name of the image to be created, used also for RG name and Image name and VM name
* vmsize...default "Standard_B2s", other possible: Standard_NC6, Standard_NC6s_v3, Standard_NC4as_T4_v3
* ostype...version of OS, currently supported: `Ubuntu18`, `Windows`, `Ubuntu20`
* version...specific version of the image or "latest" to fetch the latest version available in Azure Marketplace
* nologin..whether to explicitly go without loging,  default: $false,
* hidden..use hidden Marketplace offering, default: $false,
* aml...  DSVM Attach to AML Workspace (currently  only firewall settings), default: $false


**From Build pipeline, a.k.a. from VHD**

```powershell
.\create_dsvm_from_build.ps1 -n this-is-my-vm-name
```
parameters:

* URL...from build pipeline, URL to blob (VHD) with SAS Token
* name...name of the image to be created, used also for RG name and Image name and VM name
* vmsize...default "Standard_B2s", other possible: Standard_NC6, Standard_NC6s_v3, Standard_NC4as_T4_v3
* ostype...version of OS, currently supported: `Ubuntu18`, `Windows`, `Ubuntu20`
* nologin...whether to explicitly login to azcopy, default: false
* onlybuild..do not copy VHD first, only create the VM (assuming the VHD is already downloaded)
    

