#!/bin/bash
# $Id: createazvm.sh 440 2021-12-30 10:11:13Z bpahlawa $
# initially created by Bram Pahlawanto 25-June-2020
# $Author: bpahlawa $
# Modified by: bpahlawa
# $Date: 2021-12-30 18:11:13 +0800 (Thu, 30 Dec 2021) $
# $Revision: 440 $

LOGFILE=/tmp/$0.log
THISVM=$(hostname)
SCRIPTNAME=${0%.*}
ISCURRVMAZURE=0

> $LOGFILE


dig 2>>$LOGFILE 1>/dev/null
[[ $? -ne 0 ]] && echo -e "dig command is not available, please install this command...\nFor RHEL/Centos:   yum install bind-utils\nFor Debian/Ubuntu: apt install dnsutils\nFor Arch Linux:    pacman -S bind-tools\n" | tee -a $LOGFILE && exit 1


[[ ! -f ${SCRIPTNAME}.env ]] && echo "${SCRIPTNAME}.env parameter file doesnt exists... exiting... " | tee -a $LOGFILE && exit 1
. ${SCRIPTNAME}.env


typeset -l VMNAME
[[ "$1" != "" ]] && VMNAME="$1" || VMNAME=${VMNAME}

LOGFILE=/tmp/${0}-${VMNAME}.log

mv /tmp/$0.log $LOGFILE

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

CHECKVM=$(az group show --name $RESOURCEGROUP --output table | grep "Run \`az login\`")

if [ "$CHECKVM" != "" ]
then
  echo -n "Trying to perform Device login...."
  az login
  [[ $? -ne 0 ]] && echo -e " Failed!\nUnable to login !!.. exiting... " && exit 1
  az account set -s $SID 2>>$LOGFILE 1>/dev/null
  [[ $? -ne 0 ]] && echo -e "\nFailed to run az account set -s $SID ......exiting..." | tee -a $LOGFILE && exit 1
  echo -e " OK\n"
fi

if [ "$RESOURCEGROUP" = "" ]
then
   echo -n "Retrieving Resource Group from current VM $THISVM...."
   VMID=`az vm list --query "[?name=='$THISVM'].id" --subscription $SUBSCRIPTIONID -o tsv 2>>$LOGFILE`
   [[ "$VMID" = "" ]] && echo -e "\nThis VM $THISVM does not exist within subscription $SUBSCRIPTIONID.... exiting..." && echo -e "\n$VMID\n" && exit 1
   RESOURCEGROUP=`echo $VMID | awk -F'/' '{print $5}'`
   echo -e " $RESOURCEGROUP...\n"
else
   echo -n "Checking Resource Group $RESOURCEGROUP...."
   az group show --name $RESOURCEGROUP --output table 2>>$LOGFILE 1>/dev/null
   if [ $? -ne 0 ]
   then
       ERRMSG=$(tail -4 $LOGFILE | grep "To re-authenticate,")
       if [ "$ERRMSG" != "" ]
       then
          echo -e "\nError message $ERRMSG..."
          echo -e "\nTrying to run do az login..."
          az login
       else
          echo -e "\nResource Group $RESOURCEGROUP doesnt exits.. exiting..." && exit 1
       fi
   else
       echo -e " OK\n"
   fi
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
      echo -n "Checking Virtual Network $VNET...."
      az network vnet show --name $VNET -g $RESOURCEGROUP --output table 2>>$LOGFILE 1>/dev/null
      if [ $? -ne 0 ]
      then
         if [ "$ISCURRVMAZURE" = "1" ]
         then
	     echo -e "\nVNET $VNET doesnt exits.. therefore trying to use current VM's VNET $CURRVNET..." 
	     VNET="$CURRVNET"
         else
             echo -e "Not-Available...\n"
	     echo -n "Creating Virtual Network $VNET....."
	     az network vnet create --subscription $SUBSCRIPTIONID --resource-group $RESOURCEGROUP --name $VNET --address-prefix "${ADDRPREFIX}" --subnet-name $SUBNET --location $LOCATION 2>>$LOGFILE 1>/dev/null
             [[ $? -ne 0 ]] && echo -e "\nFailed to run az network vnet create failed.... exiting..." && exit 1
         fi
      else
         echo -e " OK\n"
      fi
   fi


   echo -n "Retrieving SUBNET information from current VM $THISVM...."
   CURRSUBNET=`echo $NICID | awk -F'/' '{print $(NF)}'`
   [[ "$CURRSUBNET" = "" ]] && echo -e " Failed! (on-prem VM)\n" || echo -e " $CURRSUBNET...\n"
   if [ "$SUBNET" = "" ]
   then
      [[ "$CURRSUBNET" = "" ]] && echo "Unable to find SUBNET from either config or current VM...exiting..." && exit 1
      echo -e "SUBNET is not defined... therefore using current VM's SUBNET $CURRSUBNET...."
      SUBNET="$CURRSUBNET"
   else
      echo -n "Checking subnet $SUBNET...."
      az network vnet subnet show --name $SUBNET -g $RESOURCEGROUP --vnet-name $VNET --output table 2>>$LOGFILE 1>/dev/null
      if [ $? -ne 0 ]
      then
         echo -n "\nSubnet $SUBNET doesnt exits.. checking whether address prefix is defined..."
         if [ "$ADDRPREFIX" = "" ] 
         then
             echo "Enforcing to use current VM's SUBNET $CURRSUBNET.." && SUBNET="$CURRSUBNET" || echo -e " OK\n"
         else
             echo -n "Creating....."
             echo -e "\nwith address prefix $ADDRPREFIX...."
             az network vnet subnet create -n $SUBNET -g $RESOURCEGROUP --vnet-name $VNET --address-prefix $ADDRPREFIX 2>>$LOGFILE 1>/dev/null
             [[ $? -ne 0 ]] && echo -e "\nFaild to create SUBNET $SUBNET...exiting..." && exit 1 || echo -e " OK\n"
         fi
      else
         echo -e " OK\n"
      fi

   fi


   echo -n "Checking Location $LOCATION ....."
   LOCAVAIL=`az account list-locations --query  "[?name=='$LOCATION']" 2>>$LOGFILE | grep $LOCATION`

   [[ "$LOCAVAIL" = "" ]] && echo -e "\nLocation $LOCATION is not available... here is the available locations:" && az account list-locations --query  "[name]" && exit 1
   echo -e " OK\n"


   echo -n "Creating Public-IP ${VMNAME}_publicip...."
   az network public-ip create -n ${VMNAME}_publicip -g $RESOURCEGROUP --dns-name $VMNAME --reverse-fqdn "${VMNAME}.${LOCATION}.cloudapp.azure.com" -l $LOCATION --allocation-method Static 2>>$LOGFILE 1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\nFailed to create Public-IP ${VMNAME}_publicip ...exiting.." && exit 1
   echo -e " OK\n"
   
   echo -n "Creating NIC ${NICNAME}...."
   az network nic create -n ${NICNAME} -g $RESOURCEGROUP --subnet $SUBNET --vnet-name $VNET -l $LOCATION --public-ip-address ${VMNAME}_publicip  2>>$LOGFILE 1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\nFailed to create NIC ${NICNAME} ...exiting.." && exit 1
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
                 #az vm image list --query "[?contains(urn,'windows')]" --all -o table 2>&1 | tee -a $LOGFILE
                 echo -e "\naz vm image list --offer windows --all -o table\n"
                 echo -e "Exiting.. "
                 exit 1
             fi
          fi
          sleep 10
   
   else
   
       if [ "$SSHPUBLICKEY" != "" ]
       then
          echo -n "Checking public key for this user $USER..."
          [[ ! -f ~/.ssh/id_rsa.pub ]] && echo -n " CREATING..." && ssh-keygen -f ~/.ssh/id_rsa -P "" && [[ $? -ne 0 ]] && echo -e "\nFailed to create public key for user $USER ...exiting.." && exit 1
          echo  -e " OK\n"
          SSHPUBLICKEY="$(cat ~/.ssh/id_rsa.pub)"
       else
          echo -e "Using SSH public key that is available in the config file..."
       fi

       echo "Creating Azure Linux VM $VMNAME...."
       az vm image terms accept --urn $VMIMAGE 2>>$LOGFILE 1>/dev/null
       az vm create --name $VMNAME \
             --resource-group $RESOURCEGROUP \
             --admin-password $ADMINPASSWORD  \
             --admin-username $ADMINUSER   \
             --os-disk-name ${VMNAME}_osdisk  \
             --attach-data-disks ${VMNAME}_${DATADISK0} \
             --authentication-type all  \
             --computer-name $VMNAME  \
             --enable-agent true  \
             --generate-ssh-keys  \
             --image $VMIMAGE  \
             --location $LOCATION  \
             --nics ${NICNAME}  \
             --size $VMSIZE \
             --ssh-dest-key-path "/home/$ADMINUSER/.ssh/authorized_keys" \
             --ssh-key-values "$SSHPUBLICKEY" \
             --subscription $SUBSCRIPTIONID 2>>$LOGFILE 1>/dev/null

          if [ $? -ne 0 ]
          then
              echo -e "Error creating Azure Linux VM $VMNAME ... "
              echo -e "Do you want to list all Azure VM image related to linux such as: centos,ubuntu and suse O/S? (y/n)"; read ANS
              if [ "$ANS" = "y" ]
              then
                 echo -e "Gathering list of all Azure Windows VM image.. it may take a while.. please wait.."
                 echo -e "The output list will also be written into logfile ${LOGFILE}-CENTOS ${LOGFILE}-DEBIAN ${LOGFILE}-UBUNTU ${LOGFILE}-SUSE ..."
                 echo -e "Once you have found the image, then set VMIMAGE=the-urn-value within ${SCRIPTNAME}.env file, then re-run this script"
                 az vm image list -f CentOS --all -o table 2>&1 | tee -a ${LOGFILE}-CENTOS.txt &
                 az vm image list -f Debian --all -o table 2>&1 | tee -a ${LOGFILE}-DEBIAN.txt &
                 az vm image list -f Ubuntu --all -o table 2>&1 | tee -a ${LOGFILE}-UBUNTU.txt &
                 az vm image list -f Suse --all -o table 2>&1 | tee -a ${LOGFILE}-SUSE.txt

                 #az vm image list --query "[?contains(urn,'linux') || contains(urn,'centos') || contains(urn,'debian') || contains(urn,'ubuntu') || contains(urn,'suse')]" --all -o table 2>&1 | tee -a $LOGFILE
                 echo -e "Exiting.. "
                 exit 1
             fi
          fi
          sleep 10
     fi

else
  echo -e " OK\n"

fi


FULLVMNAME=${VMNAME}.${LOCATION}.cloudapp.azure.com

echo -n "Checking whether $VMNAME is Running...."
ISRUNNING=`az vm show --name $VMNAME -g $RESOURCEGROUP  -d --query "powerState" 2>>$LOGFILE | sed 's/["\n\r]//g'`
if [ "$ISRUNNING" != "VM running" ] 
then
   echo -e "Not Running\n"
   echo "VM $VMNAME ($FULLVMNAME) is not in Running State..."
   echo "====================Detail VM============================"
   az vm show --name $VMNAME -g $RESOURCEGROUP  -d -o table | tee -a $LOGFILE
   echo "..Exiting..."
   exit 1
fi
echo -e "OK\n"

if [ "$ISCURRVMAZURE" = "0" ]
then
   echo -n "Creating NSG $NSGNAME......."
   az network nsg create -n ${NSGNAME} -g $RESOURCEGROUP -l $LOCATION 2>>$LOGFILE 1>/dev/null
   [[ $? -ne 0 ]] && echo "\nError creating NSG ${NSGNAME}...exiting..." && exit 1
   echo -e " OK\n"


   echo -n "Retrieving your PUBLIC IP address......."
   which dig 2>>$LOGFILE 1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\ndig command is not available... please install it and re-run this script... exiting..." && exit 1

   PUBLICIPADDR=`dig TXT +short o-o.myaddr.l.google.com @ns1.google.com 2>>$LOGFILE| sed 's/"//g'`

   if [ "$PUBLICIPADDR" = "" ]
   then
      echo  "Unable to retrieve public IP address.... please enter it manually..."
      read -p "Your Public IP address is: " PUBLICIPADDR
      echo "You have entered pulic ip address $PUBLICIPADDR ..., if this is wrong then ssh command will fail and this script will be terminated...."
   else
      echo -e " $PUBLICIPADDR\n"
   fi

   if [[ "$VMIMAGE" =~ .*Windows.* ]]
   then
      echo -n "Adding Terminal service rule to NSG ${NSGNAME}....."
      az network nsg rule create -g $RESOURCEGROUP --nsg-name $NSGNAME -n ${NSGNAME}_RDP --priority 1000 \
--source-address-prefixes $PUBLICIPADDR --source-port-ranges '*' \
--destination-address-prefixes '*' --destination-port-ranges 3389 --access Allow \
--protocol Tcp --description "Allow RDP port 3389" 2>>$LOGFILE 1>/dev/null
      [[ $? -ne 0 ]] && echo -e "\nError adding RDP rule to NSG $NSGNAME ......exiting.... " && exit 1
   else
      typeset -u AUTHMECH
      AUTHMECH=$AUTHMECH
      if [ "$AUTHMECH" = "AAD" ]
      then
         echo -n "Adding vm extension AADLoginForLinux for VM $VMNAME..."
         az vm extension set --publisher Microsoft.Azure.ActiveDirectory.LinuxSSH --name AADLoginForLinux --resource-group $RESOURCEGROUP --vm-name $VMNAME 2>>$LOGFILE 1>/dev/null 
         if [ $? -ne 0 ]
         then 
            echo "\nError adding VM Extension for VM $VMNAME...skipping..."  
         else
            echo -e "OK\n"
            echo -n "Assign $ADMINUSER as Administrator login on VM $VMNAME..."
            vmid=$(az vm show --resource-group $RESOURCEGROUP --name $VMNAME --query id -o tsv 2>>$LOGFILE | tr -d "\r")
            curruser=$(az account show --query user.name --output tsv 2>>$LOGFILE | tr -d "\r")
            if [ "$ADMINUSER" != "$curruser" ]
            then
                echo -e "Not Available\n"
                echo -n "Setting authentication for $ADMINUSER using login and password...and AAD authentication for User $curruser..."
            else
                echo -e "OK\n"
                echo -n "Setting AAD authentication for User $curruser..."
            fi
            az role assignment create --role "Virtual Machine Administrator Login" --assignee "$curruser" --scope $vmid 2>>$LOGFILE 1>/dev/null
            if [ $? -ne 0 ] 
            then
                if [ "$(grep ' does not have authorization to perform action' $LOGFILE)" != "" ]
                then
                   echo -e "\nYou probably not the owner of this subscription, therefore username $curruser can not be assigned as admin role..skipping..."
                else   
                   echo -e "\nError assigning user $ADMINUSER into VM $VMNAME...skipping..."
                fi
            else
                echo -e "OK\n"
            fi
         fi
      else
         echo "Setting Authenticaion mechanism to login and password as well as trusted user through SSH Public key"
      fi
            
      echo -n "Adding SSH rule to NSG ${NSGNAME}....."
      az network nsg rule create -g $RESOURCEGROUP --nsg-name $NSGNAME -n ${NSGNAME}_port22 --priority 1000 \
--source-address-prefixes $PUBLICIPADDR --source-port-ranges '*' \
--destination-address-prefixes '*' --destination-port-ranges 22 --access Allow \
--protocol Tcp --description "Allow SSH port 22" 2>>$LOGFILE 1>/dev/null
      [[ $? -ne 0 ]] && echo -e "\nError adding SSH rule to NSG $NSGNAME ......exiting.... " && exit 1
      echo -e " OK\n"
   fi

   echo -n "Updating NIC $NICNAME...."
   az network nic update -g $RESOURCEGROUP --subscription $SUBSCRIPTIONID -n $NICNAME --network-security-group $NSGNAME  2>>$LOGFILE 1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\nError updating NIC $NICNAME to add NSG $NSGNAME ......exiting.... " && exit 1
   echo -e " OK\n"
fi

if [[ "$VMIMAGE" =~ .*Windows.* ]]
then
   echo -e "\nWindows VM $VMNAME has been deployed successfully...\n"
else
   echo -n "Connecting to Linux VM $VMNAME using ssh..."
   ssh -o "StrictHostKeyChecking no" ${ADMINUSER}@${FULLVMNAME} "hostname;who am i"
   if [ $? -ne 0 ]
   then
      echo "Error in connecting to ${ADMINUSER}@${FULLVMNAME} , it could be that ssh public file was not setup/copied properly!"
      echo "Try specifying password...."
   fi
   ssh -o "StrictHostKeyChecking no" ${ADMINUSER}@${FULLVMNAME} "
echo \"$ADMINPASSWORD\" | sudo -S su - root -c \"[[ ! -d /root/.ssh ]] && mkdir /root/.ssh ; cp -f \$HOME/.ssh/authorized_keys /root/.ssh \"
"
   [[ $? -ne 0 ]] && echo -e "\nError connecting VM $VMNAME ( $FULLVMNAME ).... " && exit 1
   echo -e "OK\n"

   echo -n "Trying to run remote command as root to $FULLVMNAME ...."
   ssh -o "StrictHostKeyChecking no" root@${FULLVMNAME} "echo BRAMPAHL1TO##" >>$LOGFILE 2>&1
   if [ $(tail -3 $LOGFILE | grep "BRAMPAHL1TO##" | wc -l) -eq 0 ]
   then
      ERRMSG=$(tail -3 $LOGFILE | grep "Please login as the user ")
      echo -n "$ERRMSG ...."
      if [ "$ERRMSG" != "" ]
      then
         THEUSER=$(echo "$ERRMSG" | sed "s/.*Please login as the user \"\([a-zA-Z0-9]\+\)\" .*/\1/g")
         echo -n "Creating /opt filesystem on Linux VM $VMNAME using user $THEUSER remotely..."
         ssh -o "StrictHostKeyChecking no" ${THEUSER}@${FULLVMNAME} "
set -x
DISK=\`sudo lsblk -no NAME | grep -Ev \"\$(sudo blkid | sed \"s/^\/dev\/\([a-zA-Z]\+\).*/\1/g\")|sr0|fd0\" | tail -1\`
if [ \"\$DISK\" != \"\" ]
then
   echo \"Creating /opt disk....\"
   echo yes | sudo mkfs.ext4 /dev/\$DISK
   echo \"/dev/\$DISK /opt ext4 defaults 0 0\" | sudo tee -a /etc/fstab
fi
sudo mount /opt
"
         [[ $? -ne 0 ]] && echo -e "\nError creating filesystem /opt on VM $VMNAME ( $FULLVMNAME ).... " && exit 1
         echo -e "mounting /opt filesystem..... OK\n"
         echo -e "\nLinux VM $VMNAME has been deployed successfully...\n"

             
      else
         echo -n "Unable to create /opt filesystem on Linux VM $VMNAME using remote shell...you can do it manually!!"
      fi
   else
      echo -n "Creating /opt filesystem on Linux VM $VMNAME using remote shell..."
      ssh -o "StrictHostKeyChecking no" root@${FULLVMNAME} "
set -x
DISK=\`lsblk -no NAME | grep -Ev \"\$(blkid | sed \"s/^\/dev\/\([a-zA-Z]\+\).*/\1/g\")|sr0|fd0\" | tail -1\`
if [ \"\$DISK\" != \"\" ]
then
   echo \"Creating /opt disk....\"
   echo yes | mkfs.ext4 /dev/\$DISK
   echo \"/dev/\$DISK /opt ext4 defaults 0 0\" >> /etc/fstab
fi
mount /opt
"
      [[ $? -ne 0 ]] && echo -e "\nError creating filesystem /opt on VM $VMNAME ( $FULLVMNAME ).... " && exit 1
      echo -e "Mounting /opt filesystem... OK\n"
      echo -e "\nLinux VM $VMNAME has been deployed successfully...\n"
   fi
fi
