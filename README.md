# Collection of Azure-CLI automations
## Deploy Azure VM, install Windows 10, SSMA and SSMS (In one go)
### Pre-requisites
- Update crazvmssma.env file with Azure VM specifications (see crazvmssma.env)
- Run crazvmssma.sh script on Linux (bash script), the env file above must be located on the same directoy as the bash script

E.g:
<pre>
VMNAME=BRAMVMSSMA
#when using VNET from other resource group, use format such as: VNET:OHTER_RESOURCEGROUP
VNET=bramvm-vnet
SUBNET=bramsubnet
ADDRPREFIX="10.0.0.0/24"
RESOURCEGROUP=BramVnet
SUBSCRIPTIONID="a6244888-1234-4321-abcd-f22bb5b3fa63"
DATADISK0=datadisk0
LOCATION=eastus2
ADMINUSER=winadmin
ADMINPASSWORD=G0dkn0wsG0dkn0ws
DATADISKSIZE=64
#Valid image
#CentOS,CoreOS,Debian,openSUSE-Leap,RHEL,SLES,UbuntuLTS,Win2019Datacenter,Win2016Datacenter,Win2012R2Datacenter,Win2012Datacenter,Win2008R2SP1,Windows-10
VMIMAGE=MicrosoftWindowsDesktop:Windows-10:19h1-pro:18362.1256.2012032308
VMSIZE=Standard_D2s_v3
</pre>
### Deploy Azure VM
<pre>
./crazvmssma.sh
</pre>

## Deploy Azure SQL Pool Synapse (Formerly SQL Datawarehouse)
### Pre-requisites
- Update crazsqldw.env file with Azure VM specifications (see crazsqldw.env)
- Run crazsqldw.sh script on Linux (bash script), the env file above must be located on the same directoy as the bash script


## Deploy Azure VM (either Windows or Linux VM)
### Pre-requisites
- Update createazvm.env file with Azure VM specifications (see createazvm.env)
- Run createazvm.sh script on Linux (bash script), the env file above must be located on the same directoy as the bash script
