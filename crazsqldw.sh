#!/bin/bash
# $Id: crazsqldw.sh 363 2020-10-29 15:00:53Z bpahlawa $
# initially created by Bram Pahlawanto 25-June-2020
# $Author: bpahlawa $
# Modified by: bpahlawa
# $Date: 2020-10-29 23:00:53 +0800 (Thu, 29 Oct 2020) $
# $Revision: 363 $


LOGFILE=/tmp/$0.log
THISVM=$(hostname)
SCRIPTNAME=${0%.*}
CURRDIR=`pwd`

dig 2>/dev/null 1>/dev/null
[[ $? -ne 0 ]] && echo -e "dig command is not available, please install this command...\nFor RHEL/Centos:   yum install bind-utils\nFor Debian/Ubuntu: apt install dnsutils\nFor Arch Linux:    pacman -S bind-tools\n" && exit 1

[[ ! -f ${SCRIPTNAME}.env ]] && echo "$SCRIPTNAME.env parameter file doesnt exists... exiting... " && exit 1
. ${SCRIPTNAME}.env

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
   [[ $? -ne 0 ]] && echo -e "\nResource Group $RESOURCEGROUP doesnt exits.. exiting..." && exit 1
   echo -e " OK\n"
fi

echo -n "Checking whether Azure Synapse is available....." 
az sql db show --name $DBNAME -g $RESOURCEGROUP --subscription $SUBSCRIPTIONID 2>>$LOGFILE 1>/dev/null

if [ $? -ne 0 ]
then
   echo -e "doesnt exist.....Creating it....\n"

   echo -e "Creating Azure synapse with the following settings:\n"
   echo -e "Server Name       : $SERVERNAME"
   echo -e "SQL DB Pool Name  : $DBNAME"
   [[ "$COLLATION" = "" ]] && echo -e "Collation         : default" ||  echo -e "Collation         : $COLLATION" 
   echo -e "Service Objective : $SVCOBJECTIVE"
   echo -e "Maximum Storage   : $MAXSTORAGE"
   echo -e "Location          : $LOCATION\n"

   echo -n "Checking whether Azure SQL Server $SERVERNAME exists..."
   az sql server show -n $SERVERNAME -g $RESOURCEGROUP  2>>$LOGFILE 1>/dev/null
   
   if [ $? -ne 0 ]
   then
      echo -n "creating.."
      az sql server create -n $SERVERNAME -g $RESOURCEGROUP --admin-user $SQLUSER --admin-password $SQLPASS -e true  -l $LOCATION --minimal-tls-version $TLSVER 2>>$LOGFILE 1>/dev/null
      [[ $? -ne 0 ]] && echo -e "\nFailed to create Azure SQL Server $SERVERNAME ...exiting.." && exit 1
   fi
   echo -e "OK\n"

   echo -n "Retrieving your PUBLIC IP address......."
   which dig 2>/dev/null 1>/dev/null
   [[ $? -ne 0 ]] && echo -e "\ndig command is not available... please install it and re-run this script... exiting..." && echo "Unable to find dig command!!" >> $LOGFILE && exit 1

   PUBLICIPADDR=`dig TXT +short o-o.myaddr.l.google.com @ns1.google.com | sed 's/"//g' 2>>$LOGFILE`

   if [ "$PUBLICIPADDR" = "" ]
   then
      echo  "Unable to retrieve public IP address.... please enter it manually..."
      read -p "Your Public IP address is: " PUBLICIPADDR
      echo "You have entered pulic ip address $PUBLICIPADDR ..., if this is wrong then you will not be able to connect to Azure Synapse!!"
   else
      echo -e " $PUBLICIPADDR\n"
   fi

   echo -n "Creating firewall rule for Public IP address $PUBLICIPADDR ...."
   az sql server firewall-rule create -g $RESOURCEGROUP --server $SERVERNAME --name ${SERVERNAME}_clientip --start-ip-address $PUBLICIPADDR --end-ip-address $PUBLICIPADDR 2>>$LOGFILE 1>/dev/null
   if [ $? -ne 0 ]
   then
      if [ `echo $VNET | grep ":" | wc -l` -ne 0 ]
      then
         echo -e "\nFailed to add firewall rule for Public IP $PUBLICIPADDR on VNET located on resource group $OTHRGFORVNET.. skipping..."
      else
         echo -e "\nFailed to add firewall rule for Public IP $PUBLICIPADDR ...exiting.." && exit 1
      fi
   else   
      echo -e "OK\n"
   fi

   if [ "$VNET" != "" ]
   then
      echo -n "Checking whether Virtual Network $VNET exists....."
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
         az network vnet show --name $VNET -g $RESOURCEGROUP --output table 2>>$LOGFILE 1>/dev/null
         if [ $? -ne 0 ]
         then
             echo -e "Not-Available..."
             echo -n "Creating Virtual Network $VNET....."
             az network vnet create --subscription $SUBSCRIPTIONID --resource-group $RESOURCEGROUP --name $VNET --address-prefix "${ADDRPREFIX}" --subnet-name $SUBNET --location $LOCATION 2>>$LOGFILE 1>/dev/null
             [[ $? -ne 0 ]] && echo -e "\nFailed to run az network vnet create failed.... exiting..." && exit 1
         fi
         echo -e " OK\n"
      fi

      echo -n "Gathering subnet $SUBNET...."
      SUBNETID=$(az network vnet subnet show --name $SUBNET  -g ${OTHRGFORVNET:-$RESOURCEGROUP} --vnet-name $VNET --query "id" -o tsv 2>>$LOGFILE | tr -d "\r")
      [[ $? -ne 0 ]] && echo -e "Failed to retrieve SUBNET $SUBNET from resource group ${OTHRGFORVNET:-$RESOURCEGROUP}...exiting..." && exit 1

 
      echo -n "Gathering Server ID of $SERVERNAME....."
      SERVERID=`az sql server show -n $SERVERNAME -g $RESOURCEGROUP --query "id" -o json 2>>$LOGFILE|cut -f2 -d\"`
      if [ "$SERVERID" != "" ]
      then
         PRIVENDPOINT="${SERVERNAME}_privendpoint"
         echo -e "OK\n"
         echo -n "Creating private endpoint using VNET $VNET and Subnet $SUBNET ........."
         az network private-endpoint create --name ${PRIVENDPOINT} -g $RESOURCEGROUP -l $LOCATION --subnet "$SUBNETID" --private-connection-resource-id "$SERVERID" --group-id sqlServer --connection-name "${SERVERNAME}_conn" 2>>$LOGFILE 1>/dev/null
         [[ $? -ne 0 ]] && echo -e "\nFailed to create private endpoint using VNET $VNET and subnet $SUBNET...ignoring.." || echo -e "OK\n"

         echo -n "Checking private DNS Zone to server $SERVERNAME..."
         az network private-dns zone show -n "privatelink.database.windows.net" -g $RESOURCEGROUP 2>>$LOGFILE 1>/dev/null
         if [ $? -ne 0 ]
         then 
             echo -e "Not-Available...\n"
             echo -n "Creating private DNS Zone to server $SERVERNAME..."
             az network private-dns zone create -g $RESOURCEGROUP --name  "privatelink.database.windows.net" 2>>$LOGFILE 1>/dev/null
             [[ $? -ne 0 ]] && echo -e "\nFailed to create private DNS zone...ignoring.." || echo -e "OK\n"
         else
             echo -e "OK\n"
         fi
        
         PRIVDNSLINK="${SERVERNAME}_privdnslink"
         echo -n "Checking private DNS link to VNET $VNET..."
         az network private-dns link vnet show -n $PRIVDNSLINK -g $RESOURCEGROUP --zone-name "privatelink.database.windows.net" 2>>$LOGFILE 1>/dev/null
         if [ $? -ne 0 ]
         then 
             echo -e "Not-Available...\n"
             echo -n "Creating private DNS link to VNET $VNET..."
             az network private-dns link vnet create  -g $RESOURCEGROUP --zone-name  "privatelink.database.windows.net" --name $PRIVDNSLINK --virtual-network $VNET --registration-enabled false  2>>$LOGFILE 1>/dev/null
             [[ $? -ne 0 ]] && echo -e "\nFailed to create private DNS link to VNET $VNET...ignoring.." || echo -e "OK\n"
         else
             echo -e "OK\n"
         fi

         PRIVENDPOINTDNS="priv-end-dns-$SERVERNAME"
         echo -n "Checking private endpoint DNS..."
         az network private-endpoint dns-zone-group show -g $RESOURCEGROUP --endpoint-name ${PRIVENDPOINT} --name $PRIVENDPOINTDNS --private-dns-zone "privatelink.database.windows.net"  2>>$LOGFILE 1>/dev/null
         if [ $? -ne 0 ]
         then 
             echo -e "Not-Available...\n"
             echo -n "Creating private endpoint DNS..."
             az network private-endpoint dns-zone-group create -g $RESOURCEGROUP --endpoint-name ${PRIVENDPOINT} --name $PRIVENDPOINTDNS --private-dns-zone "privatelink.database.windows.net" --zone-name sql 2>>$LOGFILE 1>/dev/null
             [[ $? -ne 0 ]] && echo -e "\nFailed to create private endpoint DNS..ignoring.." || echo -e "OK\n"
         else
             echo -e "OK\n"
         fi

      else
          echo -e "Failed...\nUnable to gather Server ID from $SERVERNAME..exiting..." 
          exit 1
      fi

    
   fi
   
   echo -n "Creating Azure Synapse Database $DBNAME on Server $SERVERNAME ..."
         
   if [ "$COLLATION" = "" ]
   then
       az sql db create -n $DBNAME -g $RESOURCEGROUP -s $SERVERNAME --max-size $MAXSTORAGE --service-objective $SVCOBJECTIVE -e Datawarehouse 2>>$LOGFILE 
   else
       az sql db create -n $DBNAME -g $RESOURCEGROUP -s $SERVERNAME --max-size $MAXSTORAGE --collation $COLLATION --service-objective $SVCOBJECTIVE -e Datawarehouse 2>>$LOGFILE 
   fi

   [[ $? -ne 0 ]] && echo -e "\nFailed to create Azure Synapse Database $DBNAME ...exiting.." && exit 1
   echo -e "OK\n"

   echo -e "Azure Synapse Database $DBNAME on Server $SERVERNAME has been created successfully"
else
   echo -e "Azure Synapse Database $DBNAMe on Server $SERVERNAME is currently existing..."
    
fi
