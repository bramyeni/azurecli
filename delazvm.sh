#!/bin/bash
# $Id: delazvm.sh 450 2022-05-04 09:26:57Z bpahlawa $
# initially created by Bram Pahlawanto 25-June-2020
# $Author: bpahlawa $
# Modified by: bpahlawa
# $Date: 2022-05-04 17:26:57 +0800 (Wed, 04 May 2022) $
# $Revision: 450 $

LOGFILE=/tmp/$0.log
THISVM=$(hostname)
SCRIPTNAME=${0%.*}
ISCURRVMAZURE=0

> $LOGFILE


dig 2>>$LOGFILE 1>/dev/null
[[ $? -ne 0 ]] && echo -e "dig command is not available, please install this command...\nFor RHEL/Centos:   yum install bind-utils\nFor Debian/Ubuntu: apt install dnsutils\nFor Arch Linux:    pacman -S bind-tools\n" | tee -a $LOGFILE && exit 1

[[ $SUBSCRIPTIONID = "" ]] && echo "Please set SUBSCRIPTIONID using export SUBSCRIPTIONID command... exiting..." && exit 1

CURIFS="$IFS"
typeset -l VMNAME
if [ "$1" != "" ]
then
   if [[ "$1" =~ .*,.* ]]
   then
      IFS=','
      read -ra VMNAMES <<< "$1"   # str is read into an array as tokens separated by IFS
   else
      VMNAMES="$1"
   fi
else
   echo "Please specify VMNAME or list of VMNAME (comma separated) to delete ...."
   exit 1
fi
IFS=$CURIFS


delete_nic()
{
     for IDTODEL in $(az network nic list --query [*].ipConfigurations[].id  | grep "$VMNAME" | sed "s/,\|\"//g")
     do
        echo -n "Detaching NIC device $IDTODEL from public-ip......"
        az network nic update --ids "$IDTODEL" --remove ipConfigurations[0].publicIpAddress 2>>$LOGFILE 1>/dev/null
        [[ $? -eq 0 ]] && echo -e "OK\n" || echo -e "Failed\n"
        echo -n "Detaching NIC device $IDTODEL from NSG......"
        az network nic update --ids "$IDTODEL" --remove networkSecurityGroup 2>>$LOGFILE 1>/dev/null
        [[ $? -eq 0 ]] && echo -e "OK\n" || echo -e "Failed\n"
        echo -n "Deleting NIC device $IDTODEL ......"
        az network nic delete --ids "$IDTODEL" 2>>$LOGFILE 1>/dev/null
        [[ $? -eq 0 ]] && echo -e "OK\n" || echo -e "Failed\n"
     done

     for IDTODEL in $(az network nsg list -o json --query [*].securityRules[*].id | grep "$VMNAME" | sed "s/,\|\"//g")
     do
        echo -n "Deleting NSG $IDTODEL ......"
        az network nsg delete --ids "$IDTODEL" 2>>$LOGFILE 1>/dev/null
        [[ $? -eq 0 ]] && echo -e "OK\n" || echo -e "Failed\n"
     done

     for IDTODEL in $(az network public-ip list --query [*].id  | grep "$VMNAME" | sed "s/,\|\"//g")
     do
        echo -n "Deleting public-ip $IDTODEL ......"
        az network public-ip delete --ids "$IDTODEL" 2>>$LOGFILE 1>/dev/null
        [[ $? -eq 0 ]] && echo -e "OK\n" || echo -e "Failed\n"
     done
}


delete_disks()
{
   for IDTODEL in $(az disk list --query [*].id  | grep "$VMNAME" | sed "s/,\|\"//g")
     do
        echo -n "Deleting disks device $IDTODEL ......"
        az disk delete --ids "$IDTODEL" 2>>$LOGFILE 1>/dev/null
        [[ $? -eq 0 ]] && echo -e "OK\n" || echo -e "Failed\n"
     done
}
   

echo -n "Checking az command has been installed....."
[[ -d $(pwd)/bin ]] && export PATH=$(pwd)/bin:$PATH
az --version
if [ $? -ne 0 ]
then
   [[ -d ~/lib/azure-cli ]] && rm -rf ~/lib/azure-cli
   curl -L https://aka.ms/InstallAzureCli -o installaz 
   sed -i "s|< \$_TTY|<<\!|g" installaz
   echo -e "\n\n!" >> installaz
   bash installaz
   [[ $? -ne 0 ]] && echo -e "\nFailed to install az command....exiting..." | tee -a $LOGFILE && exit 1

else
  az config set auto-upgrade.enable=yes
  az config set auto-upgrade.prompt=no
  if [ $? -ne 0 ]
  then
     echo -e "az is already the latest version.."
  else
     echo -e " OK\n"
  fi
fi
export PATH=$(pwd)/bin:$PATH

echo -n "Checking SUBSCRIPTION $SUBSCRIPTIONID...."
SID=`az account list --output tsv 2>>$LOGFILE | grep $SUBSCRIPTIONID | awk '{print $3}'`
[[ "$SID" = "" ]] && echo -e "\nSubscription ID $SID is not available...please choose different subscription id.. exiting... " && echo "Your subscription id choices are: " && az account list --output table && az login && [[ $? -ne 0 ]] && echo "Unable to login !!.. exiting... " && exit 1
echo -e " OK\n"

echo -n "Using subscription ID $SID...."
az account set -s $SID 2>>$LOGFILE 1>/dev/null
[[ $? -ne 0 ]] && echo -e "\nFailed to run az account set -s $SID ......exiting..." | tee -a $LOGFILE && exit 1
echo -e " OK\n"


CHECKVM=$(az vm list --output table | grep "Run \`az login\`")

CHECKEXPIREDLOGIN=$(az vm list --output table 2>&1 | grep "The refresh token has expired or is invalid due to sign-in frequency checks by conditional access")

if [ "$CHECKEXPIREDLOGIN" != "" ]
then
  echo "Trying to relogin (due to the refresh token has expired or sign-in frequency checks by conditional access)"
  az login --scope https://management.core.windows.net//.default   
  [[ $? -ne 0 ]] && echo -e " Failed!\nUnable to login !!.. exiting... " && exit 1
  az account set -s $SID 2>>$LOGFILE 1>/dev/null
  [[ $? -ne 0 ]] && echo -e "\nFailed to run az account set -s $SID ......exiting..." | tee -a $LOGFILE && exit 1
  echo -e " OK\n"
fi

for VMNAME in "${VMNAMES[@]}"
do

  export VMNAME

  if [ "$CHECKVM" != "" ]
  then
    echo -n "Trying to perform Device login...."
    az login
    [[ $? -ne 0 ]] && echo -e " Failed!\nUnable to login !!.. exiting... " && exit 1
    az account set -s $SID 2>>$LOGFILE 1>/dev/null
    [[ $? -ne 0 ]] && echo -e "\nFailed to run az account set -s $SID ......exiting..." | tee -a $LOGFILE && exit 1
    echo -e " OK\n"
  else
    VMLIST=$(az vm list --output table)
    if [ $(echo $VMLIST | grep "$VMNAME" | wc -l) -eq 0 ]
    then
       delete_nic
    fi
  fi
  
  echo -n "Checking whether VM $VMNAME is available....." 
  for IDTODELETE in $(az vm list -o json --query [*].[id,storageProfile.osDisk.managedDisk.id,storageProfile.dataDisks[*].managedDisk.id] | grep "$VMNAME" | sed "s/,\|\"//g")
  do
     if [ $(echo $IDTODELETE |  grep "virtualMachines" | wc -l) -ne 0 ]
     then
        VMAVAIL=1
        echo -e "OK\n"
        echo -n "Deleting Virtual Machine $VMNAME ...." 
        az vm delete --yes --ids "$IDTODELETE" 2>>$LOGFILE 1>/dev/null
        [[ $? -eq 0 ]] && echo -e "OK\n" || echo -e "Failed\n"
     else  
        if [ $(echo $IDTODELETE |  grep "disks" | wc -l) -ne 0 ]
        then
           echo -n "Deleting disks $IDTODELETE ...."
           az disk delete --yes --ids "$IDTODELETE" 2>>$LOGFILE 1>/dev/null
           [[ $? -eq 0 ]] && echo -e "OK\n" || echo -e "Failed\n"
        fi
     fi
  done
  
  [[ "$VMAVAIL" != "1" ]] && echo -e "Deleted\n"
  
  delete_nic
  delete_disks

done
