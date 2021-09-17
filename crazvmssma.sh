#!/bin/bash
# $Id: crazvmssma.sh 426 2021-09-06 02:44:45Z bpahlawa $
# initially created by Bram Pahlawanto 25-June-2020
# $Author: bpahlawa $
# Modified by: bpahlawa
# $Date: 2021-09-06 10:44:45 +0800 (Mon, 06 Sep 2021) $
# $Revision: 426 $


ODACFILE="ODAC193Xcopy_x64.zip"
LOGFILE=/tmp/$0.log
THISVM=$(hostname)
SCRIPTNAME=${0%.*}
ISCURRVMAZURE=0
CURRDIR=`pwd`

dig 2>/dev/null 1>/dev/null
[[ $? -ne 0 ]] && echo -e "dig command is not available, please install this command...\nFor RHEL/Centos:   yum install bind-utils\nFor Debian/Ubuntu: apt install dnsutils\nFor Arch Linux:    pacman -S bind-tools\n" && exit 1


[[ ! -f ${SCRIPTNAME}.env ]] && echo "${SCRIPTNAME}.env parameter file doesnt exists... exiting... " && exit 1
. ${SCRIPTNAME}.env


typeset -l VMNAME
[[ "$1" != "" ]] && VMNAME="$1" || VMNAME=${VMNAME}

[[ ! "$VMIMAGE" =~ .*Windows.* ]] && echo -e "This script only apply to windows operating system!! ..exiting..." && exit 1

NSGNAME="${VMNAME}_nsg"
NICNAME="${VMNAME}_nic"

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

else
  echo -e " OK\n"
fi

export PATH=$(pwd)/bin:$PATH

echo -n "Checking SUBSCRIPTION $SUBSCRIPTIONID...."
SID=`az account list --output tsv | grep $SUBSCRIPTIONID | awk '{print $3}'`
[[ "$SID" = "" ]] && echo -e "\nSubscription ID $SID is not available...please choose different subscription id.. exiting... " && echo "Your subscription id choices are: " && az account list --output table && az login && [[ $? -ne 0 ]] && echo "Unable to login !!.. exiting... " && exit 1
echo -e " OK\n"

echo -n "Using subscription ID $SID...."
az account set -s $SID 2>$LOGFILE 1>/dev/null
[[ $? -ne 0 ]] && echo -e "\nFailed to run az account set -s $SID ......exiting..." && exit 1
echo -e " OK\n"

if [ "$RESOURCEGROUP" = "" ]
then
   echo -n "Retrieving Resource Group from current VM $THISVM...."
   VMID=`az vm list --query "[?name=='$THISVM'].id" --subscription $SUBSCRIPTIONID -o tsv 2>>$LOGFILE`
   [[ "$VMID" = "" ]] && echo -e "\nThis VM $THISVM does not exist within subscription $SUBSCRIPTIONID.... exiting..." && exit 1
   RESOURCEGROUP=`echo $VMID | awk -F'/' '{print $5}'`
   echo -e " $RESOURCEGROUP...\n"
else
   echo -n "Checking Resource Group $RESOURCEGROUP...."
   az group show --name $RESOURCEGROUP --output table 2>>$LOGFILE 1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\nResource Group $RESOURCEGROUP doesnt exist.. exiting..." && exit 1
   echo -e " OK\n"
fi

echo -n "Checking whether VM $VMNAME is available....." 
az vm show --name $VMNAME -g $RESOURCEGROUP --query "name" 2>>$LOGFILE 1>/dev/null

if [ $? -ne 0 ]
then
   echo -e "doesnt exist.....Creating it....\n"

   echo -n "Retrieving NIC information from current VM $THISVM...."
   CURRNIC=`az vm nic list --vm-name $THISVM -g $RESOURCEGROUP --query "[].id" -o tsv 2>>$LOGFILE`
   if [ "$CURRNIC" != "" ]
   then
      CURRNICNAME=`echo $CURRNIC | awk -F'/' '{print $NF}'`
      echo -e " $CURRNICNAME...\n"

      echo -n "Retrieving VNET information from current VM $THISVM...."
      NICID=`az network nic show --ids "$CURRNIC" --query "ipConfigurations[].subnet[].id" -o tsv 2>>$LOGFILE`
      CURRVNET=`echo $NICID | awk -F'/' '{print $(NF-2)}'`
      echo -e " $CURRVNET...\n"
      ISCURRVMAZURE=1
   else
      ISCURRVMAZURE=0
      echo -e "\nThis is not Azure VM....\n"
   fi

   if [ "$VNET" = "" ]
   then
      [[ "$CURRVNET" = "" ]] && echo "Unable to find VNET from either config or current VM...exiting..." && exit 1
      echo -e "VNET is not defined... therefore using current VM's VNET $CURRVNET......"
      VNET="$CURRVNET"
   else
      OTHRGFORVNET=$(echo $VNET | cut -f1 -d:)
      if [ "$OTHRGFORVNET" != "$(echo $VNET | cut -f2 -d:)" ]
      then
         VNET=$(echo $VNET | cut -f2 -d:)
         echo -n "Gathering Virtual Network $VNET from different resource group $OTHRGFORVNET...."
         az network vnet show --name $VNET -g $OTHRGFORVNET --output table 2>>$LOGFILE 1>/dev/null
         [[ $? -ne 0 ]] && echo -e "\nFailed to retrieve VNET $VNET from resource group $OTHRGFORVNET.. exiting...." && exit 1
         echo -e "OK\n"
      else
         OTHRGFORVNET=""
         echo -n "Checking Virtual Network $VNET...."
         az network vnet show --name $VNET -g $RESOURCEGROUP --output table 2>>$LOGFILE 1>/dev/null
         if [ $? -ne 0 ]
         then
            if [ "$ISCURRVMAZURE" = "1" ]
            then
                echo -e "\nVNET $VNET doesnt exist.. therefore trying to use current VM's VNET $CURRVNET..."
                VNET="$CURRVNET"
            else
                echo -e "Not-Available...\n"
                echo -n "Creating Virtual Network $VNET....."
                az network vnet create --subscription $SUBSCRIPTIONID --resource-group $RESOURCEGROUP --name $VNET --address-prefix "${ADDRPREFIX}" --subnet-name $SUBNET --location $LOCATION 2>>$LOGFILE 1>/dev/null
                [[ $? -ne 0 ]] && echo -e "\nFailed to run az network vnet create failed.... exiting..." && exit 1
                echo -e "OK\n"
            fi
         else
            echo -e " OK\n"
         fi
      fi
   fi


   echo -n "Retrieving SUBNET information from current VM $THISVM...."
   CURRSUBNET=`echo $NICID | awk -F'/' '{print $(NF)}'`
   echo -e " $CURRSUBNET...\n"
   if [ "$SUBNET" = "" ]
   then
      [[ "$CURRSUBNET" = "" ]] && echo "Unable to find SUBNET from either config or current VM...exiting..." && exit 1
      echo -e "SUBNET is not defined... therefore using current VM's SUBNET $CURRSUBNET...."
      SUBNET="$CURRSUBNET"
   else
      echo -n "Checking subnet $SUBNET...."
      SUBNETID=$(az network vnet subnet show --name $SUBNET  -g ${OTHRGFORVNET:-$RESOURCEGROUP} --vnet-name $VNET --query "id" -o tsv 2>>$LOGFILE | tr -d "\r")
      if [ "$SUBNETID" = "" ]
      then
         echo -e "\nSubnet $SUBNET doesnt exist.. checking whether address prefix is defined..."
         if [ "$ADDRPREFIX" = "" ] 
         then
             echo "Enforcing to use current VM's SUBNET $CURRSUBNET.." && SUBNET="$CURRSUBNET" || echo -e " OK\n"
         else
             echo "Checking whether address prefix clashes..."
             RETADDRPREFIX=$(az network vnet show -g $RESOURCEGROUP --name $VNET --query addressSpace.addressPrefixes -o tsv 2>>$LOGFILE | tr -d "\r")
             if [ "$RETADDRPREFIX" = "" ]
             then
                echo "Error occured while retrieving address prefix..."
                cat $LOGFILE
                exit 1
             elif [ "$ADDRPREFIX" != "$RETADDRPREFIX" ]
             then
                echo -e "\nUsing address prefix from current vnet $VNET which is $RETADDRPREFIX \nignoring address prefix from config file $ADDRPREFIX"
                ADDRPREFIX=$RETADDRPREFIX
             fi
                echo -n "Creating....."
                echo -e "with address prefix $ADDRPREFIX...."
                SUBNETID=$(az network vnet subnet create -n $SUBNET -g $RESOURCEGROUP --vnet-name $VNET --address-prefix "$ADDRPREFIX" --query "id" -o tsv 2>>$LOGFILE | tr -d "\r")
                [[ "$SUBNETID" = "" ]] && echo -e "\nFaild to create SUBNET $SUBNET...exiting...\nit may be address prefix has been used or any other subnet is using it" && cat $LOGFILE | grep "subnet" && exit 1 || echo -e " OK\n"
         fi
      else
         echo -e "OK\n"
      fi
   fi


   echo -n "Checking Location $LOCATION ....."
   LOCAVAIL=`az account list-locations --query  "[?name=='$LOCATION']" | grep $LOCATION 2>>$LOGFILE`

   [[ "$LOCAVAIL" = "" ]] && echo -e "\nLocation $LOCATION is not available... here is the available locations:" && az account list-locations --query  "[name]" && exit 1
   echo -e " OK\n"


   echo -n "Creating Public-IP ${VMNAME}_publicip...."
   az network public-ip create -n ${VMNAME}_publicip -g $RESOURCEGROUP --dns-name $VMNAME --reverse-fqdn "${VMNAME}.${LOCATION}.cloudapp.azure.com" -l $LOCATION --allocation-method Static 2>>$LOGFILE 1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\nFailed to create Public-IP ${VMNAME}_publicip ...exiting.." && exit 1
   echo -e " OK\n"
   
   echo -n "Creating NIC ${NICNAME}...."
   az network nic create -n ${NICNAME} -g $RESOURCEGROUP --subnet "${SUBNETID}" -l $LOCATION --public-ip-address ${VMNAME}_publicip  2>>$LOGFILE 1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\nFailed to create NIC ${NICNAME} ...exiting.." && cat $LOGFILE && exit 1
   echo -e " OK\n"

   echo -n "Creating Data DISK ${VMNAME}_${DATADISK0} size $DATADISKSIZE Gb...."
   az disk create -g $RESOURCEGROUP -n ${VMNAME}_${DATADISK0} --size-gb $DATADISKSIZE --sku Premium_LRS -l $LOCATION 2>>$LOGFILE 1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\nFailed to create Data DISK ${VMNAME}_${DATADISK0} ...exiting.." && exit 1
   echo -e " OK\n"
   
   if [[ "$VMIMAGE" =~ .*Windows.* ]]
   then
       echo "Creating Azure Windows VM $VMNAME...."
       az vm create --name $VMNAME \
             --resource-group $RESOURCEGROUP \
             --admin-password $ADMINPASSWORD  \
             --admin-username $ADMINUSER   \
             --os-disk-name ${VMNAME}_osdisk  \
             --attach-data-disks ${VMNAME}_${DATADISK0} \
             --computer-name $VMNAME  \
             --enable-agent true  \
             --image $VMIMAGE  \
             --location $LOCATION  \
             --nics ${NICNAME}  \
             --size $VMSIZE \
             --subscription $SUBSCRIPTIONID 2>>$LOGFILE 1>/dev/null

          if [ $? -ne 0 ]
          then
              echo -e "Error creating Azure Windows VM $VMNAME ... "
              echo -e "Do you want to list all Azure VM image related to windows O/S? (y/n)"; read ANS
              if [ "$ANS" = "y" ]
              then
                 echo -e "Gathering list of all Azure Windows VM image.. it may take a while.. please wait.."
                 echo -e "The output list will also be written into logfile $LOGFILE ..."
                 echo -e "Once you have found the image, then set VMIMAGE=the-urn-value within ${SCRIPTNAME}.env file, then re-run this script"
                 az vm image list --offer windows --all -o table 2>&1 | tee -a $LOGFILE
                 echo -e "\naz vm image list --offer windows --all -o table\n"
                 echo -e "Exiting.. "
                 exit 1
             fi
          fi
          sleep 10
   
   else
   
       echo -e "Can not build Azure VM to install SSMA on operating system other than Windows" | tee -a $LOGFILE
       exit 1
   
   fi

else
  echo -e " OK\n"

fi


FULLVMNAME=${VMNAME}.${LOCATION}.cloudapp.azure.com

echo -n "Checking whether $VMNAME is Running...."
ISRUNNING=`az vm show --name $VMNAME -g $RESOURCEGROUP  -d --query "powerState" 2>/dev/null | sed 's/["\n\r]//g' 2>>$LOGFILE`
if [ "$ISRUNNING" != "VM running" ] 
then
   echo "VM $VMNAME ($FULLVMNAME) is not in Running State..."
   echo "====================Detail VM============================"
   az vm show --name $VMNAME -g $RESOURCEGROUP  -d -o table | tee -a $LOGFILE
   echo "..Exiting..."
   exit 1
else
   echo -e " OK\n"
fi

if [ "$ISCURRVMAZURE" = "0" ]
then
   echo -n "Creating NSG $NSGNAME......."
   az network nsg create -n ${NSGNAME} -g $RESOURCEGROUP -l $LOCATION 2>>$LOGFILE 1>/dev/null
   [[ $? -ne 0 ]] && echo "\nError creating NSG ${NSGNAME}...exiting..." && exit 1
   echo -e " OK\n"


   echo -n "Retrieving your PUBLIC IP address......."
   which dig 2>/dev/null 1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\ndig command is not available... please install it and re-run this script... exiting..." && echo "Unable to find dig command!!" >> $LOGFILE && exit 1

   PUBLICIPADDR=`dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | sed 's/"//g' 2>>$LOGFILE`

   if [ "$PUBLICIPADDR" = "" ]
   then
      echo  "Unable to retrieve public IP address.... please enter it manually..."
      read -p "Your Public IP address is: " PUBLICIPADDR
      echo "You have entered pulic ip address $PUBLICIPADDR ..., if this is wrong then ssh command will fail and this script will be terminated...."
   else
      echo -e " $PUBLICIPADDR\n"
   fi

   echo -n "Adding Terminal service rule to NSG ${NSGNAME}_RDP....."
   az network nsg rule create -g $RESOURCEGROUP --nsg-name $NSGNAME -n ${NSGNAME}_RDP --priority 1000 \
--source-address-prefixes $PUBLICIPADDR --source-port-ranges '*' \
--destination-address-prefixes '*' --destination-port-ranges 3389 --access Allow \
--protocol Tcp --description "Allow RDP port 3389" 2>>$LOGFILE 1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\nError adding RDP rule to NSG $NSGNAME ......exiting.... " && exit 1
   echo -e " OK\n"

   echo -n "Adding Remote shell service rule to NSG ${NSGNAME}_SSH....."
   az network nsg rule create -g $RESOURCEGROUP --nsg-name $NSGNAME -n ${NSGNAME}_SSH --priority 1100 \
--source-address-prefixes $PUBLICIPADDR --source-port-ranges '*' \
--destination-address-prefixes '*' --destination-port-ranges 22 --access Allow \
--protocol Tcp --description "Allow RDP port 22" 2>>$LOGFILE 1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\nError adding RDP rule to NSG $NSGNAME ......exiting.... " && exit 1
   echo -e " OK\n"

   echo -n "Updating NIC $NICNAME...."
   az network nic update -g $RESOURCEGROUP --subscription $SUBSCRIPTIONID -n $NICNAME --network-security-group $NSGNAME 2>>$LOGFILE 1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\nError updating NIC $NICNAME to add NSG $NSGNAME ......exiting.... " && exit 1
   echo -e " OK\n"

   echo -n "Checking public key for this user $USER..."
   [[ ! -f ~/.ssh/id_rsa.pub ]] && echo -n " CREATING..." && ssh-keygen -f ~/.ssh/id_rsa -P "" 2>>$LOGFILE && [[ $? -ne 0 ]] && echo -e "\nFailed to create public key for user $USER ...exiting.." && exit 1
   echo  -e " OK\n"

   PUBLICKEY=`cat ~/.ssh/id_rsa.pub`
   ISRUNNING=""
   while [ "$ISRUNNING" != "VM running" ]
   do
       echo -e "Waiting for windows $VMNAME to be up and running....$ISRUNNING"
       ISRUNNING=`az vm show --name $VMNAME -g $RESOURCEGROUP  -d --query "powerState" 2>/dev/null | sed 's/["\n\r]//g' 2>>$LOGFILE`
       sleep 10
   done

   echo -n "Running Powershell command on windows VM $VMNAME..."
   az vm run-command invoke -g $RESOURCEGROUP --subscription $SUBSCRIPTIONID -n $VMNAME  --command-id RunPowershellScript --scripts  "
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Start-Service sshd
Set-Service -name sshd -StartupType Automatic
\$authfile=\"\$env:ALLUSERSPROFILE\ssh\administrators_authorized_keys\"
\$pubkey = \"$PUBLICKEY\"
\$pubkey | out-file -encoding ASCII \$authfile
if (Test-Path \$authfile)
{
   \$AUTHORIZEDKEYS=\"\$authfile\"
} else
{
   \$AUTHORIZEDKEYS=\"\$env:HOMEPATH\.ssh\authorized_keys\"
}
\$acl = get-acl \$AUTHORIZEDKEYS
\$acl.SetAccessRuleProtection(\$true, \$false)
\$administratorsRule = New-Object system.security.accesscontrol.filesystemaccessrule(\"$ADMINUSER\",\"FullControl\",\"Allow\")
\$systemRule = New-Object system.security.accesscontrol.filesystemaccessrule(\"SYSTEM\",\"FullControl\",\"Allow\")
\$groupnone = New-Object System.Security.Principal.NTAccount 'none'
\$acl.setGroup(\$groupnone)
\$acl.SetAccessRule(\$administratorsRule)
\$acl.SetAccessRule(\$systemRule)
\$acl | Set-Acl 
New-NetFirewallRule -DisplayName \"Allow TCP 22\" -Direction Inbound -Action Allow -EdgeTraversalPolicy Allow -Protocol TCP -LocalPort 22
if (! (Test-Path \"c:\\Download\"))
{new-item -Path \"c:\\Download\" -type directory}
restart-computer -force
" 2>>$LOGFILE | sed 's|\\n|\n|g' | tee -a $LOGFILE
   [[ $? -ne 0 ]] && echo -e "\nError Running Powershell command on VM $VMNAME ......exiting.... " && exit 1
   echo -e " OK\n"

   echo -e "Restarting windows VM $VMNAME...."
   sleep 10
   ISRUNNING=""
   while [ "$ISRUNNING" != "VM running" ]
   do
       echo -e "Waiting for windows $VMNAME to be up and running....$ISRUNNING"
       ISRUNNING=`az vm show --name $VMNAME -g $RESOURCEGROUP  -d --query "powerState" 2>/dev/null | sed 's/["\n\r]//g' 2>>$LOGFILE`
       sleep 10
   done
   

   echo -n "Checking whether $ODACFILE exists...." 
   if [ "$(ls -1 $ODACFILE 2>>$LOGFILE)" != "" ]
   then
      echo -e " OK\n"
      echo -e "Checking whether $ODACFILE has been uploaded..."
      UPLOADEDFILE=`ssh -o "StrictHostKeyChecking no" ${ADMINUSER}@${FULLVMNAME} "dir /B c:\\\\download\\\\${ODACFILE}" 2>>$LOGFILE`
      if [ "$UPLOADEDFILE" = "" ]
      then
         echo -e "Copying $ODACFILE to ${ADMINUSER}@${FULLVMNAME}:c:/download ..."
         scp -o "StrictHostKeyChecking no" $ODACFILE ${ADMINUSER}@${FULLVMNAME}:c:/download
         [[ $? -ne 0 ]] && echo -e "Failed to copy the above file...." && exit 1
      else
         echo -e "File $ODACFILE is already uploaded to ${ADMINUSER}@${FULLVMNAME}:c:/download ..."
      fi
   else
      echo -e "File $ODACFILE doesnt exist.. \nyou must download from oracle website the $ODACFILE and place this file side by side with this script.." | tee -a $LOGFILE
      echo -e "\nPlease download from this link http://download.oracle.com/otn/other/ole-oo4o/ODAC193Xcopy_x64.zip,\nyou need to login and accept oracle license agreement.. exiting..." | tee -a $LOGFILE
      exit 1
   fi

   SCRIPT_LINE=`awk '/^__ENCODED_SCRIPT__/ {print NR + 1; exit 0; }' $CURRDIR/$0`
   tail -n+$SCRIPT_LINE $CURRDIR/$0 | base64 -d > /tmp/installssma.ps1
   scp -o "StrictHostKeyChecking no" /tmp/installssma.ps1 ${ADMINUSER}@${FULLVMNAME}:c:/

   [[ $? -ne 0 ]] && echo -e "\nError copying script to $FULLVMNAME ...exiting.... " && exit 1
   rm -f /tmp/installssma.ps1

   echo -n "Running Powershell command on Azure VM...."
   az vm run-command invoke -g $RESOURCEGROUP --subscription $SUBSCRIPTIONID -n $VMNAME  --command-id RunPowershellScript --scripts  "c:\\installSSMA.ps1 -username $ADMINUSER
start-sleep 5
remove-item c:\\installSSMA.ps1" 2>>$LOGFILE  | sed 's|\\n|\n|g' | tee -a $LOGFILE
   [[ $? -ne 0 ]] && echo -e "\nError Running Powershell script on VM $VMNAME ......exiting.... " && exit 1
   echo -e " OK\n"
   
fi

exit 0
__ENCODED_SCRIPT__
77u/IyB+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fn5+fg0KIyAkSWQ6IGluc3RhbGxTU01B
LnBzMSA0OSAyMDIwLTExLTAyIDA1OjM1OjI1WiBicGFobGF3YSAkDQojICREYXRlOiAyMDIwLTExLTAyIDEzOjM1OjI1ICswODAw
IChNb24sIDAyIE5vdiAyMDIwKSAkDQojICRSZXZpc2lvbjogNDkgJA0KIyAkQXV0aG9yOiBicGFobGF3YSAkDQojIA0KDQojIFBh
cmFtZXRlciB0byBiZSBwYXNzZWQgYnkgdGhpcyBwcm9ncmFtIHdoZW4gcnVubmluZyBhcyBhZG1pbmlzdHJhdG9yDQpwYXJhbSAo
DQogICAgW1BhcmFtZXRlcihNYW5kYXRvcnkpXQ0KICAgIFtzdHJpbmddJFVzZXJuYW1lLA0KICAgIFtzdHJpbmddJEZsYWcgPSAw
DQopDQoNCiRnbG9iYWw6dG9yYXVybD0iaHR0cHM6Ly9kb3dubG9hZHMuc291cmNlZm9yZ2UubmV0L3Byb2plY3QvdG9yYS90b3Jh
LzMuMi4wL1RvcmEuMy4yLjI4My5SZWxlYXNlLjY0Yml0LnppcD9yPWh0dHBzJTNBJTJGJTJGc291cmNlZm9yZ2UubmV0JTJGcHJv
amVjdHMlMkZ0b3JhJTJGZmlsZXMlMkZ0b3JhJTJGMy4yLjAlMkZUb3JhLjMuMi4yODMuUmVsZWFzZS42NGJpdC56aXAlMkZkb3du
bG9hZCZ0cz0xNjAzOTg4NzA1Ig0KJGdsb2JhbDpiYXNpY29yYXVybCA9ICJodHRwczovL2Rvd25sb2FkLm9yYWNsZS5jb20vb3Ru
X3NvZnR3YXJlL250L2luc3RhbnRjbGllbnQvMTk4MDAvaW5zdGFudGNsaWVudC1iYXNpYy13aW5kb3dzLng2NC0xOS44LjAuMC4w
ZGJydS56aXA/eGRfY29fZj0yYzYzZGY5YWUyOGUwZDI5ODU3MTU5NzcyOTk2MTU0OCINCiRnbG9iYWw6VVJMU1NNQSA9ICJodHRw
czovL2Rvd25sb2FkLm1pY3Jvc29mdC5jb20vZG93bmxvYWQvMS8yLzYvMTI2QjBCRTUtNzczMS00MDcwLTlBQjEtNzM4MjhENDE5
NzgxL1NTTUFmb3JPcmFjbGVfOC4xNC4wLm1zaSINCiRnbG9iYWw6VVJMZXh0U1NNQSA9ICJodHRwczovL2Rvd25sb2FkLm1pY3Jv
c29mdC5jb20vZG93bmxvYWQvMS8yLzYvMTI2QjBCRTUtNzczMS00MDcwLTlBQjEtNzM4MjhENDE5NzgxL1NTTUFmb3JPcmFjbGVF
eHRlbnNpb25QYWNrXzguMTQuMC5tc2kiDQokZ2xvYmFsOlVSTHNzbXMgPSAiaHR0cHM6Ly9ha2EubXMvc3Ntc2Z1bGxzZXR1cCIN
CiRnbG9iYWw6dGVtcGRvd25sb2FkID0gImM6XGRvd25sb2FkIg0KJGdsb2JhbDpTU01BZmlsZSA9ICJTU01BZm9yT3JhY2xlXzgu
MTQuMC5tc2kiDQokZ2xvYmFsOlNTTUFleHRmaWxlID0gIlNTTUFmb3JPcmFjbGVFeHRlbnNpb25QYWNrXzguMTQuMC5tc2kiDQok
R2xvYmFsOkxvZ2ZpbGUgPSAiJGVudjp3aW5kaXJcdGVtcFxpbnN0YWxsU1NNQS5sb2ciDQokZ2xvYmFsOm9kYWNmaWxlID0gIk9E
QUMxOTNYY29weV94NjQiDQokZ2xvYmFsOmluc3RhbnRjbGllbnQgPSAiaW5zdGFudGNsaWVudCINCiRnbG9iYWw6c3Ntc2ZpbGUg
PSAiU1NNUy1TZXR1cC1FTlUuZXhlIg0KJGdsb2JhbDp0b3JhID0gInRvcmEiDQokZ2xvYmFsOnN0YXJ0bWVudSA9ICJDOlxQcm9n
cmFtRGF0YVxNaWNyb3NvZnRcV2luZG93c1xTdGFydCBNZW51XFByb2dyYW1zXCINCiRnbG9iYWw6cHVibGljZGVza3RvcCA9ICJD
OlxVc2Vyc1xQdWJsaWNcRGVza3RvcCINCgpbTmV0LlNlcnZpY2VQb2ludE1hbmFnZXJdOjpTZWN1cml0eVByb3RvY29sID0gIlRs
cyxUbHMxMSxUbHMxMiIKDQoNCiMgZnVuY3Rpb24gdG8gZGlzcGxheSBtZXNzYWdlIGFuZCBhbHNvIHdyaXRlIHRvIGEgbG9nZmls
ZQ0KRnVuY3Rpb24gV3JpdGUtT3V0cHV0QW5kTG9nDQp7DQogICBQYXJhbSAoW3N0cmluZ10kTWVzc2FnZSkNCiAgIHdyaXRlLWhv
c3QgIiRtZXNzYWdlIg0KICAgQWRkLWNvbnRlbnQgIiRHbG9iYWw6TG9nZmlsZSIgLXZhbHVlICIkbWVzc2FnZSINCn0NCg0KZnVu
Y3Rpb24gQ3JlYXRlLU5ld1Byb2ZpbGUgew0KIA0KICAgIFBhcmFtDQogICAgKA0KICAgICAgICAjIFBhcmFtMSBoZWxwIGRlc2Ny
aXB0aW9uDQogICAgICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5PSR0cnVlKV0NCiAgICAgICAgW3N0cmluZ10kVXNlck5hbWUNCiAN
CiAgICApDQogIA0KICAgIGlmICghIChHZXQtTG9jYWxVc2VyKS5uYW1lLmNvbnRhaW5zKCR1c2VybmFtZSkpDQogICAgew0KICAg
ICAgICBXcml0ZS1Ib3N0ICJMb2NhbCB1c2VyICR1c2VybmFtZSBkb2VzbnQgZXhpc3RzLi5leGl0aW5nLi4uIg0KICAgICAgICBy
ZXR1cm4gJGZhbHNlDQogICAgfSANCiAgICANCiAgICAgICAgIA0KICAgIA0KICAgICRtZXRob2ROYW1lID0gJ1VzZXJFbnZDUCcN
CiAgICAkc2NyaXB0Om5hdGl2ZU1ldGhvZHMgPSBAKCk7DQogDQogICAgaWYgKC1ub3QgKFtTeXN0ZW0uTWFuYWdlbWVudC5BdXRv
bWF0aW9uLlBTVHlwZU5hbWVdJE1ldGhvZE5hbWUpLlR5cGUpDQogICAgew0KICAgICAgICAkZGxsPSJ1c2VyZW52LmRsbCINCiAg
ICAgICAgJG1ldGhvZFNpZ25hdHVyZT0iaW50IENyZWF0ZVByb2ZpbGUoW01hcnNoYWxBcyhVbm1hbmFnZWRUeXBlLkxQV1N0cild
IHN0cmluZyBwc3pVc2VyU2lkLGANCiAgICAgICAgIFtNYXJzaGFsQXMoVW5tYW5hZ2VkVHlwZS5MUFdTdHIpXSBzdHJpbmcgcHN6
VXNlck5hbWUsYA0KICAgICAgICAgW091dF1bTWFyc2hhbEFzKFVubWFuYWdlZFR5cGUuTFBXU3RyKV0gU3RyaW5nQnVpbGRlciBw
c3pQcm9maWxlUGF0aCwgdWludCBjY2hQcm9maWxlUGF0aCkiDQoNCiAgICAgICAgJHNjcmlwdDpuYXRpdmVNZXRob2RzICs9IFtQ
U0N1c3RvbU9iamVjdF1AeyBEbGwgPSAkZGxsOyBTaWduYXR1cmUgPSAkbWV0aG9kU2lnbmF0dXJlOyB9DQogICAgICAgIA0KDQog
ICAgICAgICRuYXRpdmVNZXRob2RzQ29kZSA9ICRzY3JpcHQ6bmF0aXZlTWV0aG9kcyB8IEZvckVhY2gtT2JqZWN0IHsgIg0KICAg
ICAgICBbRGxsSW1wb3J0KGAiJCgkXy5EbGwpYCIpXQ0KICAgICAgICBwdWJsaWMgc3RhdGljIGV4dGVybiAkKCRfLlNpZ25hdHVy
ZSk7DQogICAgIiB9DQogDQogICAgQWRkLVR5cGUgQCINCiAgICAgICAgdXNpbmcgU3lzdGVtOw0KICAgICAgICB1c2luZyBTeXN0
ZW0uVGV4dDsNCiAgICAgICAgdXNpbmcgU3lzdGVtLlJ1bnRpbWUuSW50ZXJvcFNlcnZpY2VzOw0KICAgICAgICBwdWJsaWMgc3Rh
dGljIGNsYXNzICRNZXRob2ROYW1lIHsNCiAgICAgICAgICAgICRuYXRpdmVNZXRob2RzQ29kZQ0KICAgICAgICB9DQoiQA0KDQog
DQoNCiAgICB9DQogDQogICAgJGxvY2FsVXNlciA9IE5ldy1PYmplY3QgU3lzdGVtLlNlY3VyaXR5LlByaW5jaXBhbC5OVEFjY291
bnQoIiRVc2VyTmFtZSIpOw0KDQogICAgDQogICAgJHVzZXJTSUQgPSAkbG9jYWxVc2VyLlRyYW5zbGF0ZShbU3lzdGVtLlNlY3Vy
aXR5LlByaW5jaXBhbC5TZWN1cml0eUlkZW50aWZpZXJdKQ0KICAgIA0KICAgICRzYiA9IG5ldy1vYmplY3QgU3lzdGVtLlRleHQu
U3RyaW5nQnVpbGRlcigyNjApOw0KICAgICRwYXRoTGVuID0gJHNiLkNhcGFjaXR5Ow0KIA0KICAgIFdyaXRlLVZlcmJvc2UgIkNy
ZWF0aW5nIHVzZXIgcHJvZmlsZSBmb3IgJFVzZXJuYW1lIjsNCiANCiAgICB0cnkNCiAgICB7DQogICAgICAgIFtVc2VyRW52Q1Bd
OjpDcmVhdGVQcm9maWxlKCR1c2VyU0lELlZhbHVlLCAkVXNlcm5hbWUsICRzYiwgJHBhdGhMZW4pIHwgT3V0LU51bGw7DQogICAg
ICAgIHJldHVybiAkdHJ1ZTsNCiAgICB9DQogICAgY2F0Y2gNCiAgICB7DQogICAgICAgIFdyaXRlLUVycm9yICRfLkV4Y2VwdGlv
bi5NZXNzYWdlOw0KICAgICAgICByZXR1cm4gJGZhbHNlOw0KICAgIH0NCn0NCg0KIyBmdW5jdGlvbiBkb3dubG9hZCBmaWxlIGZy
b20gaW50ZXJuZXQNCkZ1bmN0aW9uIERvd25sb2FkLUZpbGUgew0KICAgIFBhcmFtKA0KICAgICAgICBbUGFyYW1ldGVyKE1hbmRh
dG9yeSldDQogICAgICAgIFtzdHJpbmddICRuYW1lLA0KICAgICAgICBbUGFyYW1ldGVyKE1hbmRhdG9yeSldDQogICAgICAgIFtz
dHJpbmddICR1cmwNCiAgICApDQoNCiAgIyBEaXNwbGF5IG1lc3NhZ2Ugb2YgZG93bmxvYWRpbmcgZmlsZQ0KICBpZiAoICAoIFRl
c3QtUGF0aCAtcGF0aCAiJGdsb2JhbDp0ZW1wZG93bmxvYWRcJG5hbWUiICkgLWVxICAkZmFsc2UpDQogICAgew0KICAgICAgICBX
cml0ZS1PdXRwdXRBbmRMb2cgKCdEb3dubG9hZGluZyB7MH0gaW5zdGFsbGVyIGZyb20gezF9IC4uJyAtZiAkbmFtZSwgJHVybCk7
IA0KICAgICAgICB0cnkgeyANCiAgICAgICAgICAgICAgSW52b2tlLVdlYlJlcXVlc3QgLXVyaSAkdXJsIC1vdXRmaWxlICIkZ2xv
YmFsOnRlbXBkb3dubG9hZFwkbmFtZSIgLVVzZUJhc2ljUGFyc2luZyAtVXNlckFnZW50IFtNaWNyb3NvZnQuUG93ZXJTaGVsbC5D
b21tYW5kcy5QU1VzZXJBZ2VudF06OkNocm9tZSAtRXJyb3JBY3Rpb24gc3RvcA0KICAgICAgICAgICAgfSANCiAgICAgICAgY2F0
Y2ggeyANCiAgICAgICAgICAgIA0KICAgICAgICAgICAgV3JpdGUtT3V0cHV0QW5kTG9nICJGYWlsZWQgdG8gZG93bmxvYWQgJyR1
cmwnIEVycm9yICQoJF8uRXhjZXB0aW9uLk1lc3NhZ2UpIg0KICAgICAgICAgICAgV3JpdGUtT3V0cHV0QW5kTG9nICJDaGVjayB1
cmwgJHVybCBtYXkgaGF2ZSBjaGFuZ2VkICEhLCBpZiB0aGlzIGlzIHRoZSBjYXNlIHBsZWFzZSBjaGFuZ2UgdXJsIHZhcmlhYmxl
IGluIHRoaXMgc2NyaXB0ISEiDQogICAgICAgICAgICBXcml0ZS1PdXRwdXRBbmRMb2cgIndpbGwgbm90IGluc3RhbGwgJG5hbWUu
Li4iDQogICAgICAgICAgICAgJF8uRXhjZXB0aW9uLlJlc3BvbnNlIA0KICAgICAgICAgfSANCg0KICAgICAgICAgIFdyaXRlLU91
dHB1dEFuZExvZyAiVXJsICckdXJsJyBoYXMgYmVlbiBkb3dubG9hZGVkIGludG8gJyRnbG9iYWw6dGVtcGRvd25sb2FkXCRuYW1l
JyINCiAgICAgICAgICBXcml0ZS1PdXRwdXRBbmRMb2cgKCdEb3dubG9hZGVkIHswfSBieXRlcycgLWYgKEdldC1JdGVtICRnbG9i
YWw6dGVtcGRvd25sb2FkXCRuYW1lKS5sZW5ndGgpOw0KICAgICAgICANCiAgICAgICANCiAgICB9DQogICAgZWxzZQ0KICAgIHsN
CiAgICAgICBXcml0ZS1PdXRwdXRBbmRMb2cgIkZpbGUgJyRuYW1lJyBoYXMgYmVlbiBkb3dubG9hZGVkLi4uIiANCiAgICB9DQoN
CiAgDQogDQp9DQoNCg0KRnVuY3Rpb24gRXh0cmFjdC1BcmNoaXZlKCkNCnsNCiAgIFBhcmFtKA0KICAgICAgICBbUGFyYW1ldGVy
KE1hbmRhdG9yeSldDQogICAgICAgIFtzdHJpbmddICRMaXRlcmFsUGF0aCwNCiAgICAgICAgW1BhcmFtZXRlcihNYW5kYXRvcnkp
XQ0KICAgICAgICBbc3RyaW5nXSAkRGVzdGluYXRpb25QYXRoDQogICAgKQ0KDQogICAgV3JpdGUtT3V0cHV0QW5kTG9nICJFeHRy
YWN0aW5nIEFyY2hpdmUgZnJvbSAkTGl0ZXJhbFBhdGggdG8gJERlc3RpbmF0aW9uUGF0aCINCg0KICAgIGlmICggJHBzdmVyc2lv
bnRhYmxlLlBTVmVyc2lvbi5NYWpvciAtbHQgNSApDQogICAgew0KICAgICAgICBbU3lzdGVtLlJlZmxlY3Rpb24uQXNzZW1ibHld
OjpMb2FkV2l0aFBhcnRpYWxOYW1lKCJTeXN0ZW0uSU8uQ29tcHJlc3Npb24uRmlsZVN5c3RlbSIpIHwgT3V0LU51bGwNCiAgICAg
ICAgW1N5c3RlbS5JTy5Db21wcmVzc2lvbi5aaXBGaWxlXTo6RXh0cmFjdFRvRGlyZWN0b3J5KCRMaXRlcmFsUGF0aCwgJERlc3Rp
bmF0aW9uUGF0aCkNCiAgICB9DQogICAgZWxzZQ0KICAgIHsNCiAgICAgICAgRXhwYW5kLUFyY2hpdmUgLUxpdGVyYWxQYXRoICRM
aXRlcmFsUGF0aCAtRGVzdGluYXRpb25QYXRoICREZXN0aW5hdGlvblBhdGggLWZvcmNlDQogICAgfQ0KfQ0KDQojIGZ1bmN0aW9u
IHRvIGluc3RhbGwgbXNpIGFwcGxpY2F0aW9uDQpGdW5jdGlvbiBJbnN0YWxsLUZyb21Nc2kgew0KICAgICMgcmVxdWlyZWQgcGFy
YW1ldGVycyBhcmUgbmFtZSBhbmQgdXJsDQogICAgUGFyYW0oDQogICAgICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV0NCiAgICAg
ICAgW3N0cmluZ10gJG5hbWUsDQogICAgICAgIFtQYXJhbWV0ZXIoTWFuZGF0b3J5KV0NCiAgICAgICAgW3N0cmluZ10gJHVybCwN
CiAgICAgICAgW1BhcmFtZXRlcigpXQ0KICAgICAgICBbc3dpdGNoXSAkbm9WZXJpZnkgPSAkZmFsc2UsDQogICAgICAgIFtQYXJh
bWV0ZXIoKV0NCiAgICAgICAgW3N0cmluZ1tdXSAkb3B0aW9ucyA9IEAoKQ0KICAgICkNCg0KICAgICMgb25jZSBpdCBpcyBkb3du
bG9hZGVkIGl0IHdpbGwgYmUgc3RvcmVkIGluIHRoZSBsb2NhdGlvbiB0aGF0IGlzIGFzc2lnbmVkIHRvIHRoaXMgdmFyaWFibGUN
CiAgICAkaW5zdGFsbGVyUGF0aCA9ICggIiRnbG9iYWw6dGVtcGRvd25sb2FkXHswfSIgLWYgJG5hbWUgKTsNCg0KDQogICAgIyBj
aGVjayB3aGV0aGVyIG1zaSBhcHBsaWNhdGlvbiBoYXMgYmVlbiBpbnN0YWxsZWQNCgkjIFN1cHJlc3MgZXJyb3INCiAgICAkRXJy
b3JBY3Rpb25QcmVmZXJlbmNlID0gJ1NpbGVudGx5Q29udGludWUnDQoNCg0KICAgICMgaWYgdGhlICRyZXN1bHQgdmFyaWFibGUg
aXMgbnVsbCB0aGVuIHRoZSBjb21tYW5kIGlzbnQgaW5zdGFsbGVkIA0KCSMgb3RoZXJ3aXNlIGl0IHdpbGwgZGlzcGxheSAkbmFt
ZSBoYXMgYmVlbiBpbnN0YWxsZWQgYW5kIHJldHVybiB0byBtYWluIHByb2dyYW0NCiAgICBpZiAoJHJlc3VsdCAtbmUgJG51bGwp
DQogICAgew0KICAgICAgICB3cml0ZS1vdXRwdXRBbmRMb2cgIiRuYW1lIGhhcyBiZWVuIGluc3RhbGxlZC4uIg0KICAgICAgICMg
cmV0dXJuOw0KICAgIH0NCiAgICBlbHNlDQogICAgew0KICAgICAgICBXcml0ZS1PdXRwdXRBbmRMb2cgIldpbGwgYmUgZG93bmxv
YWRpbmcgJG5hbWUgZnJvbSAkdXJsIg0KICAgIH0NCg0KICAgICMgaWYgdGhlICRpbnN0YWxsZXJwYXRoIGZpbGUgaXNudCBhdmFp
bGFibGUgdGhlbiBkb3dubG9hZCB0aGUgZmlsZQ0KICAgIGlmICggICggVGVzdC1QYXRoIC1wYXRoICRpbnN0YWxsZXJQYXRoICkg
LWVxICAkZmFsc2UpDQogICAgew0KICAgICAgIFdyaXRlLU91dHB1dEFuZExvZyAoJ0Rvd25sb2FkaW5nIHswfSBpbnN0YWxsZXIg
ZnJvbSB7MX0gLi4nIC1mICRuYW1lLCAkdXJsKTsNCiAgICAgICBJbnZva2UtV2ViUmVxdWVzdCAtVXJpICR1cmwgLU91dGZpbGUg
JGluc3RhbGxlclBhdGggLXVzZWJhc2ljcGFyc2luZzsNCiAgICAgICBXcml0ZS1PdXRwdXRBbmRMb2cgKCdEb3dubG9hZGVkIHsw
fSBieXRlcycgLWYgKEdldC1JdGVtICRpbnN0YWxsZXJQYXRoKS5sZW5ndGgpOw0KICAgIH0NCiAgICBlbHNlDQogICAgew0KICAg
ICAgIFdyaXRlLU91dHB1dEFuZExvZyAiRmlsZSAkSW5zdGFsbGVyUGF0aCBoYXMgYmVlbiBkb3dubG9hZGVkLi4uIiANCiAgICB9
DQoNCiAgICANCg0KICAgICRhcmdzID0gQCgnL2knLCJgIiRpbnN0YWxsZXJQYXRoYCIiLCAnL3F1aWV0JywgJy9xbicsIi9MKlYg
JGVudjp3aW5kaXJcdGVtcFwnJG5hbWUnLmxvZyIpOw0KICAgICRhcmdzICs9ICRvcHRpb25zOw0KDQogICAgIyBjaGVjayB3aGV0
aGVyIHBlcmwgaGFzIGJlZW4gaW5zdGFsbGVkDQogICAgJHRoZWZpbGUgPSBHZXQtQ2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAkR2xv
YmFsOnRlbXBkb3dubG9hZCAtRmlsdGVyICRuYW1lIC1SZWN1cnNlIC1mb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51
ZQ0KDQogICAgaWYgKCAkdGhlZmlsZS5GdWxsbmFtZSAtbmUgJG51bGwgKQ0KICAgIHsNCiAgICAgICBXcml0ZS1PdXRwdXRBbmRM
b2cgKCdVbmluc3RhbGxpbmcgezB9IC4uLicgLWYgJG5hbWUpOw0KICAgICAgIFdyaXRlLU91dHB1dEFuZExvZyAoIm1zaWV4ZWMg
L3VuaW5zdGFsbCAnJGluc3RhbGxlclBhdGgnIC9wYXNzaXZlIC9ub3Jlc3RhcnQiKTsNCiAgICAgICAkYXJnc3UgPSBAKCcvdW5p
bnN0YWxsJywiYCIkaW5zdGFsbGVyUGF0aGAiIiwgJy9wYXNzaXZlJywnL25vcmVzdGFydCcpOw0KICAgICAgIFN0YXJ0LXByb2Nl
c3MgbXNpZXhlYyAtd2FpdCAtQXJndW1lbnRMaXN0ICRhcmdzdSAgDQogICAgfQ0KDQogICAgIyBkaXNwbGF5IG1lc3NhZ2UNCiAg
ICBXcml0ZS1PdXRwdXRBbmRMb2cgKCdJbnN0YWxsaW5nIHswfSAuLi4nIC1mICRuYW1lKTsNCiAgICBXcml0ZS1PdXRwdXRBbmRM
b2cgKCdtc2lleGVjIHswfScgLWYgKCRhcmdzIC1Kb2luICcgJykpOw0KDQogICAgIyBleGVjdXRlIGluc3RhbGxhdGlvbg0KICAg
IFN0YXJ0LVByb2Nlc3MgbXNpZXhlYyAtV2FpdCAtQXJndW1lbnRMaXN0ICRhcmdzOw0KDQogICAgIyAgVXBkYXRlIHBhdGgNCiAg
ICAkZW52OlBBVEggPSBbRW52aXJvbm1lbnRdOjpHZXRFbnZpcm9ubWVudFZhcmlhYmxlKCdQQVRIJywgW0Vudmlyb25tZW50VmFy
aWFibGVUYXJnZXRdOjpNYWNoaW5lKTsNCg0KICAgICMgdmVyaWZ5IHdoZXRoZXIgdGhlIGFwcGxpY2F0aW9uIGlzIGluc3RhbGxl
ZCBzdWNjZXNzZnVsbHkNCiAgICBpZiAoISRub1ZlcmlmeSkgew0KICAgICAgICBXcml0ZS1PdXRwdXRBbmRMb2cgKCdWZXJpZnlp
bmcgezB9IGluc3RhbGwgLi4uJyAtZiAkbmFtZSk7DQogICAgICAgICR2ZXJpZnlDb21tYW5kID0gKCcgezB9IC0tdmVyc2lvbicg
LWYgJG5hbWUpOw0KICAgICAgICBXcml0ZS1PdXRwdXRBbmRMb2cgJHZlcmlmeUNvbW1hbmQ7DQogICAgICAgIEludm9rZS1FeHBy
ZXNzaW9uICR2ZXJpZnlDb21tYW5kOw0KICAgIH0NCg0KICAgICMgcmVtb3ZlIHRoZSBpbnN0YWxsYXRpb24gZmlsZQ0KICAgIFdy
aXRlLU91dHB1dEFuZExvZyAoJ1JlbW92aW5nIHswfSBpbnN0YWxsZXIgLi4uJyAtZiAkbmFtZSk7DQogICAgI1JlbW92ZS1JdGVt
ICRpbnN0YWxsZXJQYXRoIC1Gb3JjZTsNCg0KICAgIFdyaXRlLU91dHB1dEFuZExvZyAoJ3swfSBpbnN0YWxsIGNvbXBsZXRlLicg
LWYgJG5hbWUpOw0KfQ0KDQoNCg0KDQojIGZ1bmN0aW9uIHRvIHJlbW92ZSBhbGwgdGVtcGZpbGVzDQpGdW5jdGlvbiBSZW1vdmUt
VGVtcEZpbGVzIHsNCiAgICAkdGVtcEZvbGRlcnMgPSBAKCRnbG9iYWw6dGVtcGRvd25sb2FkKQ0KDQogICAgV3JpdGUtT3V0cHV0
QW5kTG9nICdSZW1vdmluZyB0ZW1wb3JhcnkgZmlsZXMnOw0KICAgICRmaWxlc1JlbW92ZWQgPSAwOw0KICANCiAgICBmb3JlYWNo
ICgkZm9sZGVyIGluICR0ZW1wRm9sZGVycykgew0KICAgICAgICAkZmlsZXMgPSBHZXQtQ2hpbGRJdGVtIC1MaXRlcmFsUGF0aCAk
Zm9sZGVyIC1SZWN1cnNlIC1Gb3JjZSAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZSANCg0KICAgICAgICBmb3JlYWNoICgk
ZmlsZSBpbiAkZmlsZXMpIHsNCiAgICAgICAgICAgIHRyeSB7DQogICAgICAgICAgICAgICAgUmVtb3ZlLUl0ZW0gJGZpbGUuRnVs
bE5hbWUgLVJlY3Vyc2UgLUZvcmNlIC1FcnJvckFjdGlvbiBTdG9wDQogICAgICAgICAgICAgICAgJGZpbGVzUmVtb3ZlZCsrOw0K
ICAgICAgICAgICAgfQ0KICAgICAgICAgICAgY2F0Y2ggew0KICAgICAgICAgICAgICAgICRFcnJvck1lc3NhZ2UgPSAkXy5FeGNl
cHRpb24uTWVzc2FnZQ0KICAgICAgICAgICAgICAgICRGYWlsZWRJdGVtID0gJF8uRXhjZXB0aW9uLkl0ZW1OYW1lDQogICAgICAg
ICAgICAgICAgV3JpdGUtT3V0cHV0QW5kTG9nICgiSXRlbTogJEZhaWxlZGl0ZW0sIEVycm9yOiAkRXJyb3JNZXNzYWdlIikNCiAg
ICAgICAgICAgIH0NCg0KICAgICAgICAgICAgDQogICAgICAgIH0NCiAgICB9DQoNCiAgICBXcml0ZS1PdXRwdXRBbmRMb2cgKCdS
ZW1vdmVkIHswfSBmaWxlcyBmcm9tIHRlbXBvcmFyeSBkaXJlY3RvcmllcycgLWYgJGZpbGVzUmVtb3ZlZCkNCn0NCg0KIyBmdW5j
dGlvbiB0byBjaGVjayBpbnRlcm5ldCBjb25uZWN0aW9uDQpGdW5jdGlvbiBDaGVjay1JbnRlcm5ldCgpDQp7DQoNCiAgICAkRXJy
b3JBY3Rpb25QcmVmZXJlbmNlID0gJ1NpbGVudGx5Q29udGludWUnDQoJIyBjaGVjayBjb25uZWN0aW9uIHRvIG1pY3Jvc29mdC5j
b20sIHRoaXMgaXMgdG8gZW5zdXJlIHRoYXQgdGhlIGxvY2F0aW9uIHdoZXJlIHRoZSBzY3JpcHQgaXMgcnVuIGhhcyBpbnRlcm5l
dCBjb25uZWN0aW9uDQogICAgJFJlc3VsdCA9IChJbnZva2UtV2ViUmVxdWVzdCAtdXJpICJodHRwOi8vbWljcm9zb2Z0LmNvbSIg
LUVycm9yQWN0aW9uIFNpbGVudGx5Q29udGludWUgLXVzZWJhc2ljcGFyc2luZykNCiAgICAkRXJyb3JBY3Rpb25QcmVmZXJlbmNl
ID0gJ0NvbnRpbnVlJw0KDQogICAgIyBpZiAkcmVzdWx0IGlzbnQgbnVsbCB0aGVuIGludGVybmV0IGlzIGF2YWlsYWJsZSwgb3Ro
ZXJ3aXNlIGV4aXQgb3V0DQogICAgaWYgKCRSZXN1bHQgLWVxICRudWxsKQ0KICAgIHsNCiAgICAgICAgd3JpdGUtb3V0cHV0QW5k
TG9nICJJbnRlcm5ldCBpcyBub3QgYXZhaWxhYmxlLi4uIg0KICAgICAgICBleGl0DQogICAgfQ0KDQp9DQoNCg0KDQojIGZuY3Rp
b24gdG8gbW92ZSBkaXJlY3RvcnkgaWYgZG9lc250IGV4aXN0DQpGdW5jdGlvbiBNb3ZlLURpcigpDQp7DQpQYXJhbSgNCiAgICBb
UGFyYW1ldGVyKE1hbmRhdG9yeSA9ICRUcnVlKV0NCiAgICBbU3RyaW5nXSAkU291cmNlLA0KICAgIFtTdHJpbmddICREZXN0aW5h
dGlvbikNCg0KICAgICAgICBpZiAoVGVzdC1QYXRoIC1MaXRlcmFsUGF0aCAkU291cmNlICkgDQogICAgICAgIHsNCiAgICAgICAg
ICAgIHRyeSB7DQogICAgICAgICAgICAgICBNb3ZlLUl0ZW0gLUxpdGVyYWxQYXRoICRTb3VyY2UgLURlc3RpbmF0aW9uICREZXN0
aW5hdGlvbiAtRXJyb3JBY3Rpb24gU3RvcA0KICAgICAgICAgICAgfQ0KICAgICAgICAgICAgY2F0Y2ggew0KICAgICAgICAgICAg
ICAgV3JpdGUtT3V0cHV0QW5kTG9nICJVbmFibGUgdG8gbW92ZSBkaXJlY3RvcnkgZnJvbSAnJFNvdXJjZScgdG8gJyREZXN0aW50
YWlvbicuIEVycm9yIHdhczogJF8iIC1FcnJvckFjdGlvbiBTdG9wDQogICAgICAgICAgICB9DQogICAgICAgICAgICB3cml0ZS1v
dXRwdXRhbmRMb2cgIlN1Y2Nlc3NmdWxseSBtb3ZlIGRpcmVjdG9yeSBmcm9tICckU291cmNlJyB0byAnJERlc3RpbmF0aW9uJy4i
DQogICAgICAgIH0NCiAgICAgICAgZWxzZSANCiAgICAgICAgew0KICAgICAgICAgICAgd3JpdGUtb3V0cHV0YW5kbG9nICJEaXJl
Y3RvcnkgJyRTb3VyY2UnIGRvZXNudCBleGlzdCINCiAgICAgICAgfQ0KfQ0KDQojIGZuY3Rpb24gdG8gY3JlYXRlIGRpcmVjdG9y
eSBpZiBkb2VzbnQgZXhpc3QNCkZ1bmN0aW9uIENyZWF0ZS1EaXIoKQ0Kew0KUGFyYW0oDQogICAgW1BhcmFtZXRlcihNYW5kYXRv
cnkgPSAkVHJ1ZSldDQogICAgW1N0cmluZ10gJERpcmVjdG9yeVRvQ3JlYXRlKQ0KDQogICAgICAgIGlmICgtbm90IChUZXN0LVBh
dGggLUxpdGVyYWxQYXRoICREaXJlY3RvcnlUb0NyZWF0ZSApKSANCiAgICAgICAgew0KICAgICAgICAgICAgd3JpdGUtb3V0cHV0
QW5kTG9nICJDcmVhdGluZyBEaXJlY3RvcnkgJyREaXJlY3RvcnlUb0NyZWF0ZScgLi4uIg0KICAgICAgICAgICAgdHJ5IHsNCiAg
ICAgICAgICAgICAgIE5ldy1JdGVtIC1QYXRoICREaXJlY3RvcnlUb0NyZWF0ZSAtSXRlbVR5cGUgRGlyZWN0b3J5IC1FcnJvckFj
dGlvbiBTdG9wIHwgT3V0LU51bGwgIy1Gb3JjZQ0KICAgICAgICAgICAgfQ0KICAgICAgICAgICAgY2F0Y2ggew0KICAgICAgICAg
ICAgICAgV3JpdGUtRXJyb3IgLU1lc3NhZ2UgIlVuYWJsZSB0byBjcmVhdGUgZGlyZWN0b3J5ICckRGlyZWN0b3J5VG9DcmVhdGUn
LiBFcnJvciB3YXM6ICRfIiAtRXJyb3JBY3Rpb24gU3RvcA0KICAgICAgICAgICAgfQ0KICAgICAgICAgICAgd3JpdGUtb3V0cHV0
QW5kTG9nICJTdWNjZXNzZnVsbHkgY3JlYXRlZCBkaXJlY3RvcnkgJyREaXJlY3RvcnlUb0NyZWF0ZScuIg0KICAgICAgICB9DQog
ICAgICAgIGVsc2UgDQogICAgICAgIHsNCiAgICAgICAgICAgIHdyaXRlLW91dHB1dEFuZExvZyAiRGlyZWN0b3J5ICckRGlyZWN0
b3J5VG9DcmVhdGUnIGFscmVhZHkgZXhpc3RlZCINCiAgICAgICAgfQ0KICAgICAgICAgICANCg0KfQ0KDQogICAgJFRoZWRhdGUg
PSBHZXQtRGF0ZSAtRm9ybWF0ICJkZGRkIE1NL2RkL3l5eXkgSEg6bW0gSyINCg0KICAgIFdyaXRlLU91dHB1dEFuZExvZyAiPT09
PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT1FeGVjdXRpbmcgc2NyaXB0IG9uICRUaGVkYXRlID09PT09
PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09Ig0KCQ0KICAgICMgZ2V0IHRoZSBzY3JpcHQgbmFtZQ0KCSRU
aGVTY3JpcHROYW1lID0gJE15SW52b2NhdGlvbi5NeUNvbW1hbmQuTmFtZQ0KDQogICAgIyBjaGVjayB3aGV0aGVyIHRoaXMgc2Ny
aXB0IGhhcyBiZWVuIHJ1bm5pbmcNCgkkaGFuZGxlID0gZ2V0LXByb2Nlc3MgfCB3aGVyZSB7ICRfLm5hbWUgLWxpa2UgJ3Bvd2Vy
c2hlbGwqJyB9DQoJDQoNCiAgICAjIGNoZWNrIGlmIHRoZSBwYXJhbWV0ZXIgaGFzIGJlZW4gcGFzc2VkIHRvIHRoaXMgc2NpcnB0
DQoJaWYgKCAkaGFuZGxlLmNvdW50IC1sdCA0ICkNCgl7DQoJDQoJICAgICMgZ2V0IHRoZSBzY3JpcHQgZGlyZWN0b3J5IGxvY2F0
aW9uDQogICAgICAgICRHbG9iYWw6U2NyaXB0RGlyID0gU3BsaXQtUGF0aCAkc2NyaXB0Ok15SW52b2NhdGlvbi5NeUNvbW1hbmQu
UGF0aA0KCQ0KICAgICAgICANCgkJQ2hlY2stSW50ZXJuZXQNCiAgICAgICANCg0KICAgICAgICBpZiAoIShUZXN0LVBhdGggJGds
b2JhbDp0ZW1wZG93bmxvYWQgKSl7DQogICAgICAgICAgICBDcmVhdGUtRGlyICRnbG9iYWw6dGVtcGRvd25sb2FkIH0NCg0KICAg
ICAgICANCiAgICAgICAgSW5zdGFsbC1Gcm9tTXNpIC1uYW1lICRnbG9iYWw6U1NNQWZpbGUgLXVybCAkZ2xvYmFsOlVSTFNTTUEg
LW9wdGlvbnMgIkxJQ0VOU0VfQUNDRVBURUQ9MSINCiAgICAgICAgSW5zdGFsbC1Gcm9tTXNpIC1uYW1lICRnbG9iYWw6U1NNQWV4
dGZpbGUgLXVybCAkZ2xvYmFsOlVSTGV4dFNTTUEgLW9wdGlvbnMgIkxJQ0VOU0VfQUNDRVBURUQ9MSINCg0KICAgICAgICBpZiAo
ISAodGVzdC1wYXRoICRnbG9iYWw6dGVtcGRvd25sb2FkXCRnbG9iYWw6dG9yYS56aXApKQ0KICAgICAgICB7DQogICAgICAgICAg
IERvd25sb2FkLUZpbGUgLW5hbWUgIiRnbG9iYWw6dG9yYS56aXAiIC11cmwgJGdsb2JhbDp0b3JhdXJsDQogICAgICAgIH0NCg0K
ICAgICAgICBpZiAoISAodGVzdC1wYXRoICRnbG9iYWw6dGVtcGRvd25sb2FkXCRnbG9iYWw6aW5zdGFudGNsaWVudC56aXApKQ0K
ICAgICAgICB7DQogICAgICAgICAgIERvd25sb2FkLUZpbGUgLW5hbWUgIiRnbG9iYWw6aW5zdGFudGNsaWVudC56aXAiIC11cmwg
JGdsb2JhbDpiYXNpY29yYXVybA0KICAgICAgICB9DQoNCiAgICAgICAgaWYgKCEgKHRlc3QtcGF0aCAkZ2xvYmFsOnRlbXBkb3du
bG9hZFwkZ2xvYmFsOnNzbXNmaWxlKSkgDQogICAgICAgIHsNCiAgICAgICAgICAgRG93bmxvYWQtZmlsZSAtbmFtZSAiJGdsb2Jh
bDpzc21zZmlsZSIgLXVybCAkZ2xvYmFsOnVybHNzbXMNCiAgICAgICAgfQ0KICAgICAgICANCiAgICAgICAgV3JpdGUtT3V0cHV0
QW5kTG9nICJDcmVhdGluZyB1c2VyIHByb2ZpbGUuLi4iDQogICAgICAgIENyZWF0ZS1OZXdQcm9maWxlIC1Vc2VyTmFtZSAkVXNl
cm5hbWUNCg0KICAgICAgICBXcml0ZS1PdXRwdXRBbmRMb2cgIkluc3RhbGxpbmcgU1NNUy4uLiIqDQogICAgICAgIA0KDQogICAg
ICAgIGlmICggVGVzdC1QYXRoICRnbG9iYWw6dGVtcGRvd25sb2FkXCRnbG9iYWw6c3Ntc2ZpbGUgKXsNCiAgICAgICAgICAgIHN0
YXJ0LXByb2Nlc3MgLVdvcmtpbmdEaXJlY3RvcnkgIiRnbG9iYWw6dGVtcGRvd25sb2FkIiAtRmlsZVBhdGggIiRnbG9iYWw6c3Nt
c2ZpbGUiIC1Bcmd1bWVudGxpc3QgIiAvSW5zdGFsbCAvUXVpZXQgL05vcmVzdGFydCAvTG9nICRlbnY6d2luZGlyXHRlbXBcc3Nt
c3NldHVwIiAtd2FpdCANCiAgICAgICAgfQ0KDQoNCiAgICAgICAgJHNzbXNzaG9ydGN1dD1HZXQtQ2hpbGRJdGVtIC1MaXRlcmFs
UGF0aCAiJGdsb2JhbDpzdGFydG1lbnUiIC1maWx0ZXIgIk1pY3Jvc29mdCpNYW5hZ2VtZW50KiIgLVJlY3Vyc2UgLUVycm9yQWN0
aW9uIFNpbGVudGx5Q29udGludWUNCg0KICAgICAgICBpZiAoICRzc21zc2hvcnRjdXQuRnVsbE5hbWUgLW5lICRudWxsKQ0KICAg
ICAgICB7DQogICAgICAgICAgICBDb3B5LUl0ZW0gLVBhdGggJHNzbXNzaG9ydGN1dC5GdWxsTmFtZSAtRGVzdGluYXRpb24gIiRn
bG9iYWw6cHVibGljZGVza3RvcCINCiAgICAgICAgfQ0KICAgICAgICBFeHRyYWN0LUFyY2hpdmUgLUxpdGVyYWxQYXRoICIkZ2xv
YmFsOnRlbXBkb3dubG9hZFwkZ2xvYmFsOnRvcmEuemlwIiAtRGVzdGluYXRpb25QYXRoIGM6XCAtRXJyb3JBY3Rpb24gU2lsZW50
bHlDb250aW51ZQ0KDQogICAgICAgIE5ldy1JdGVtIC1JdGVtVHlwZSBTeW1ib2xpY0xpbmsgLVBhdGggIiRnbG9iYWw6cHVibGlj
ZGVza3RvcCIgLU5hbWUgIlRvcmEiIC1WYWx1ZSAiYzpcdG9yYVx0b3JhLmV4ZSIgLUZvcmNlDQogICAgICAgIA0KICAgICAgICBF
eHRyYWN0LUFyY2hpdmUgLUxpdGVyYWxQYXRoICIkZ2xvYmFsOnRlbXBkb3dubG9hZFwkZ2xvYmFsOmluc3RhbnRjbGllbnQuemlw
IiAtRGVzdGluYXRpb25QYXRoIGM6XCAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KICAgICAgICANCiAgICAgICAgaWYg
KFRlc3QtUGF0aCAiYzpcJGdsb2JhbDppbnN0YW50Y2xpZW50IiApIHsNCiAgICAgICAgICAgUmVtb3ZlLWl0ZW0gLUxpdGVyYWxQ
YXRoICJjOlwkZ2xvYmFsOmluc3RhbnRjbGllbnQiIC1SZWN1cnNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAg
ICAgIH0NCiAgICAgICAgJHRoZWluc3RhbnRjbGllbnRmaWxlPUdldC1DaGlsZEl0ZW0gLUxpdGVyYWxQYXRoIGM6XCAtRmlsdGVy
ICIkKCRnbG9iYWw6aW5zdGFudGNsaWVudClfKiIgLWZvcmNlIC1FcnJvckFjdGlvbiBTaWxlbnRseUNvbnRpbnVlDQogICAgICAg
IA0KICAgICAgICANCiAgICAgICAgaWYgKFRlc3QtUGF0aCAkdGhlaW5zdGFudGNsaWVudGZpbGUuRnVsbE5hbWUgKSB7DQogICAg
ICAgICAgICBtb3ZlLWRpciAtU291cmNlICIkKCR0aGVpbnN0YW50Y2xpZW50ZmlsZS5GdWxsbmFtZSkiIC1EZXN0aW5hdGlvbiAi
YzpcJGdsb2JhbDppbnN0YW50Y2xpZW50Ig0KICAgICAgICB9DQoNCiAgICAgICAgRXh0cmFjdC1BcmNoaXZlIC1MaXRlcmFsUGF0
aCAiJGdsb2JhbDp0ZW1wZG93bmxvYWRcJGdsb2JhbDpvZGFjZmlsZS56aXAiIC1EZXN0aW5hdGlvblBhdGggJGdsb2JhbDp0ZW1w
ZG93bmxvYWRcb2RhYyAtRXJyb3JBY3Rpb24gU2lsZW50bHlDb250aW51ZQ0KDQogICAgICAgIGlmIChUZXN0LVBhdGggJGdsb2Jh
bDp0ZW1wZG93bmxvYWRcb2RhY1xpbnN0YWxsLmJhdCApew0KICAgICAgICAgICAgc3RhcnQtcHJvY2VzcyAtV29ya2luZ0RpcmVj
dG9yeSAiJGdsb2JhbDp0ZW1wZG93bmxvYWRcb2RhYyIgLUZpbGVQYXRoICJpbnN0YWxsLmJhdCIgLUFyZ3VtZW50bGlzdCAiYWxs
IGM6XCRnbG9iYWw6aW5zdGFudGNsaWVudCBvcmFjbGVob21lIHRydWUiIC13YWl0DQogICAgICAgDQogICAgICAgIH0NCg0KDQog
ICAgICAgIFNldC1Mb2NhdGlvbiAtUGF0aCBjOlwNCiAgICAgICAgUmVtb3ZlLWl0ZW0gLUxpdGVyYWxQYXRoICIkZ2xvYmFsOnRl
bXBkb3dubG9hZCIgLVJlY3Vyc2UgLWZvcmNlDQogICAgICAgIFdyaXRlLU91dHB1dEFuZExvZyAiYG49PT09PT09PT09PT09PT09
PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09PT09
PT09PT09PT09PWBuYG4iDQp9
