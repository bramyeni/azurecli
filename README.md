# Collection of Azure-CLI automations

Any of the following Azure-cli will perform fully automated installation end to end until the environment is ready to use, the automation steps can be divided into the following:
- Based on createazvm.env, it will retrieve all necessary information to deploy VM on azure such as subscription, resource group, vnet, etc
- If some components are not available, then the script will create them automatically, such as: resource group, vnet, network interface and VM
- Initially, it will deploy 1 VM as a place to run copied createazvm.sh to deploy those master and worker nodes (as a deployer VM, this is to speed up process as the connection back and forth from on-prem to azure will be slower then having 1 dedicated VM as deployer and in fact it can use the same subnet mask to deploy those multiple VMs)
- The deployer VM will then run createazvm.sh based on the information that is provided in addon script
- After the VM is fully created/deployed and in running state, then the addon script(s) will be executed to perform any post-deployment activities
- One of the addons that is available here will install kubernetes master and N number of worker nodes, let say you have specified 1 master and 100 worker nodes then the script will create 101 VM and then use 1 node as a master (name must be set on addon script under variable name K8SMASTER) and 100 worker nodes (the base name must be specified on addon script under variable name K8SNODE E.g: lxworker, then it will create lxworker1, lxwoker2 until lxworker100)
- The kubernetes installation script setup-k8scrio.sh has been encoded into base64 and it is included into the addon script which will be executed after 101 VM nodes are completely deployed
- All ssh trusted connections between worker nodes and master node are also included in the script
- The end result will be: a kubernetes cluster with 1 master and 100 worker nodes are ready to use

## Deploy Azure VM (either Windows or Linux VM) with addon scripts
### Pre-requisites
- Update createazvm.env file with Azure VM specifications (see createazvm.env)
- Run createazvm.sh script on Linux (bash script), the env file above must be located on the same directoy as the bash script
- Create createazvm.addon.xxxxxxxx script, this script will be run after createazvm.sh is executed

### Included Addons
- Fully automated installation of additional data disk
- Fully automated installation of cubefs master and worker nodes
- Fully automated installation of kubernetes (crio library) with 1 master node and configurable no of worker nodes

### Deploy Kubernetes with 100 worker nodes
- Modified createazvm.addon.installk8s to have the following
<pre>
export K8SMASTER=lxmaster
export K8SNODE=lxworker
export NOOFWORKERS=100
</pre>
- Ensure there is no other addon script apart from createazvm.addon.installk8s, if there is other script with format createazvm.addon.xxxx then this script will be run as well (so be very careful having createazvm.addon.xxxx that is not intendedly to be run, if this exists rename it to createazvm.backup.xxxx or something like that)
- Run the script and deploy temp VM let say: lxmonitor
<pre>
./createazvm.sh lxmonior
</pre>
NOTE: this process will run as it explained above, so there will be lxmonitor, lxmaster and lxworker1 upto lxworker100 ready to run, the lxmonitor then can be deleted or it can be kept as a jumpbox 

## Delete Azure VM including underlying components
- Delete multiple VM by specifiying comma separated between VM name to be deleted (without space)
<pre>
./delazvm.sh lxmonitor,lxmaster,lxworker1,lxworker2,lxworker3
</pre>
NOTE: the above command will delete all the above VMs including all underlying components such as: disk, network interface, public-ip, nsg, etc

## Deploy Azure VM, install Windows 10, SSMA, SSMS and Oracle Instantclient 19c (In one go)
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
### Deploy Azure VM and install SSMS, SSMA and Oracle Instantclient 19c
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
