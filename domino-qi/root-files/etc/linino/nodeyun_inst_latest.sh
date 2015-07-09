# nodeyun_inst_latest.sh : A simple node.js installation script
# Copyright (C) 2014 Dog Hunter AG
# 
# Author : Arturo Rinaldi
# E-mail : arturo@doghunter.org
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# 
#
# Release v13 changelog :
#	
#	+Low level formatting before partitioning the SDCard
#
# Release v12 changelog :
# 
# 	+now the NPM settings are globally set
# 	+various bugfixes
#

#!/bin/sh

# has_sd=`mount | grep ^/dev/sda | grep 'on /overlay'`

disclaimer () {

echo ""

echo -e "DISCLAIMER :\n"

echo -e "This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details."

}

returngigs () {

	size=`fdisk -l | grep "Disk /dev/sda" | awk {'print $5'}`
	
	if [ $size -lt 64500000000 -a $size -gt 63000000000 ]
	
	  then
	    
	    sizetoformat=+'62500MB'
	    return 0
	
	elif [ $size -lt 32500000000 -a $size -gt 31000000000 ]
	
	  then
	    
	    sizetoformat=+'30500MB'
	    return 0
	
	    
	elif [ $size -lt 16500000000 -a $size -gt 15000000000 ]
	  
	  then
	    
	    sizetoformat=+'14500MB'
	    return 0
	    	
	elif [ $size -lt 8500000000 -a $size -gt 7000000000 ]
	  
	  then
	    
	    sizetoformat=+'7000MB'
	    return 0
	
	elif [ $size -lt 4500000000 -a $size -gt 3000000000 ]
	  
	  then
	    
	    sizetoformat=+'3000MB'
	    return 0
	
	elif [ $size -lt 2500000000 -a $size -gt 1000000000 ]
	
	  then
	    
	    sizetoformat=+'1000MB'
	    return 0
	    
	elif [ $size -lt 1500000000 -a $size -gt 900000000 ]
	
	  then
	    
	    sizetoformat=+'512M'
	    return 0
	    
	else
	    
	    echo "SDCard size mismatch ! ! ! Terminating the program..."
	    return 1
	    
	fi
	
}

umountsda1 () {

	if `grep -qs '/dev/sda1' /proc/mounts`
	then
	    
	    umount /dev/sda1
	    
	fi
}


umountallsda () {

	if `df | grep -qs sda`
	then
		
	    df | grep sda | awk {'print $1'} | xargs umount
		
	fi

}

swapoffallsda () {

	if `cat /proc/swaps | grep -qs sda`
	then
		
	    cat /proc/swaps | grep sda | awk {'print $1'} | xargs swapoff
		
	fi

}

formatsdcard () {
  	
  	sleep 5
	
	#Killing all existing blocks on the device
	lsof | grep /dev/sda1 | grep -v sh | awk {'print $2'} | xargs kill -9 > /dev/null 2>&1
	
	#Umounts all the sda partitions
	umountallsda
	
	#Swaps-off any activated swap partition in sda device
	swapoffallsda
	
	echo ""
	echo "Low level formatting the SDCard..."
	echo ""
	
	#Low level formatting
	dd if=/dev/zero of=/dev/sda bs=512 count=1
	
	# Creation of the primary and swap partitions
	
	echo ""
	echo "Partitioning SDCard..."
	echo ""

	echo "n
	p
	1
	
	$1	
	n
	p
	2
	
	
	t
	2
	82
	w
	"|fdisk /dev/sda 
		
	sleep 20	
	
	umountallsda

	sleep 10 

	mkfs.ext3 -L driveSD /dev/sda1
	
	sleep 10
	
	mkswap -L swapSD /dev/sda2 
    
}

umountopt () {
      
      if `grep -qs '/opt' /proc/mounts`
      then
      
	  umount /opt
	 
      fi
}


formatvfat () {

 	if [ -d '/opt' ] && `grep -qs '/opt' /proc/mounts` && `grep -qs '/dev/sda2' /proc/swaps`
	then
		
		
		ps www | grep -i [n]ode | grep -v sh | awk {'print $1'} | xargs kill -9 > /dev/null 2>&1
		
		reset-mcu
		
		lsof | grep /opt/ | grep -v sh | awk {'print $2'} | xargs kill -9 > /dev/null 2>&1
		
		lsof | grep /dev/sda2 | grep -v sh | awk {'print $2'} | xargs kill -9 > /dev/null 2>&1
		
		sleep 10

		#umountopt
		umountallsda
		
		sleep 10

		#swapoff /dev/sda2
		#swapoff -L swapSD
		swapoffallsda
		
		sleep 10
		
		echo ""
		echo "Low level formatting the SDCard..."
		echo ""
		
		#Low level formatting
		dd if=/dev/zero of=/dev/sda bs=512 count=1
		
		#Creation of the primary partition
		echo ""
		echo "Partitioning SDCard..."
		echo ""
	  
		echo "n
		p
		1
		
		
		t
		c
		w
		"|fdisk /dev/sda
		
		sleep 15
		
		umountallsda
		
		echo ""
		echo "Formatting disk to FAT32..."
		
		sleep 10
		
		mkdosfs -F 32 /dev/sda1

		sleep 10
		
		mount /dev/sda1 /mnt/sda1
	    
	    else
		
		echo "ERROR ! System not reverted !"
		
	fi
	  
	
}

logo () {
cat <<"EOT"
 _     _       _               _   _           _           _     
| |   (_)_ __ (_)_ __   ___   | \ | | ___   __| | ___     | |___ 
| |   | | '_ \| | '_ \ / _ \  |  \| |/ _ \ / _` |/ _ \ _  | / __|
| |___| | | | | | | | | (_) | | |\  | (_) | (_| |  __/| |_| \__ \
|_____|_|_| |_|_|_| |_|\___/  |_| \_|\___/ \__,_|\___(_)___/|___/

EOT
}

fstabclean () {

	#Delete tab spaces and trailing blank lines in /etc/config/fstab
	mv /etc/config/fstab /etc/config/fstab_node
	sed -i -e "s/[[:space:]]$//" /etc/config/fstab_node
	sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba' /etc/config/fstab_node > /etc/config/fstab
	rm /etc/config/fstab_node

}

fstabmod () {

uuid1=`blkid | grep "driveSD" | awk {'print $3'} | sed 's/UUID=//g' | sed -e 's/'\"'/'\''/g'`
uuid2=`blkid | grep "swapSD" | awk {'print $3'} | sed 's/UUID=//g' | sed -e 's/'\"'/'\''/g'`
#Inserts the mount points in /etc/config/fstab
cat <<EOF

#startnodejsconfig

config swap
	option uuid $uuid2
	option enabled '1'        

config mount                                 
	option target '/opt'
	option uuid $uuid1
	option fstype 'ext3'                               	
	option enabled '1'

#endnodejsconfig                  
EOF
}

prereqs () {
 
	opkg update 
	opkg install fdisk e2fsprogs mtd-utils mkdosfs lsof openssh-sftp-server psmisc
      
}

removeprereqs () {

	opkg update
	opkg remove fdisk e2fsprogs mtd-utils mkdosfs lsof openssh-sftp-server psmisc

}

bliss () {
	"$@"
	 exit 0
}

removeideino () {

	if [ -d /opt/ideino-linino ] && [ -e /opt/ideino-linino/ideino.js ]
	then
	      
	    ps www | grep -i [n]ode | grep -v sh | awk {'print $1'} | xargs kill -9 > /dev/null 2>&1
	    reset-mcu
	    #
	    opkg update
	    opkg remove ideino
	
	fi
	
}


reverttodefault (){

	#Reverts fstab
	# fstaborig > /etc/config/fstab
	mv /etc/config/fstab /etc/config/fstab_node
	
	#Delete the strings for the Node.Js setup
	sed -i '/#startnodejsconfig/,/#endnodejsconfig/d' /etc/config/fstab_node
	
	#Delete the trailing blank lines
	sed -e :a -e '/^\n*$/{$d;N;};/\n$/ba' /etc/config/fstab_node > /etc/config/fstab
	rm /etc/config/fstab_node
	
	#Reverts profile
	sed -i 's/:\/opt\/usr\/bin//g' /etc/profile  
	sed -i '/LD_LIBRARY_PATH/d' /etc/profile
	sed -i '/NODE_PATH/d' /etc/profile

	#Updates the new /etc/profile
	source /etc/profile > /dev/null
	
	#Reverts opkg.conf
	sed -i '/\/opt/d' /etc/opkg.conf
	
}

system () {

	if [ ! -d /opt ]
	then
	      mkdir /opt
	fi
	
	#Mounts the newly created partitions
	mount -t ext3 -v /dev/sda1 /opt
	#swapon /dev/sda2
	swapon -L swapSD
	
	sleep 2
	
	#Backups the /etc/fstab file
	cp /etc/config/fstab /etc/config/fstab_bak
	
	#Deleting tab and trailing spaces
	fstabclean

	sleep 2
	
	#Adding the mount entries to /etc/config/fstab
	fstabmod >> /etc/config/fstab
	echo "dest mnt /opt" >> /etc/opkg.conf

	sleep 2
	
	#Adding the /opt/usr/bin entry to the PATH variable
	opkg update
	sed -i '/PATH/ s|$|:\/opt\/usr\/bin|' /etc/profile
	
	sleep 2
	
	#Adding the /opt/usr/lib entry to the LD_LIBRARY_PATH variable
	echo "export LD_LIBRARY_PATH=/opt/usr/lib" >> /etc/profile
	echo "export NODE_PATH=/opt/usr/lib/node_modules" >> /etc/profile
	
	#Updates the /etc/profile file
	source /etc/profile > /dev/null

}


nodejs () {
	
	if [ -d /opt ] && `grep -qs '/opt' /proc/mounts`
	then
	      opkg update
	      opkg install node -d mnt
	    
	      sleep 3
		
	      #Set the temporary entries to /etc/profile
	      echo "export node=/opt/usr/bin/node" >> /etc/profile
	      echo "export npm=/opt/usr/bin/npm" >> /etc/profile    
	      source /etc/profile > /dev/null
	      
	      sleep 2
	      
	      # GLOBAL settings for npm
	      npm config set userconfig /opt/.npmrc --global
	      npm config set userignorefile /opt/.npmignore --global
	      npm config set cache /opt/.npm --global
	      npm config set tmp /opt/tmp --global
	      npm config set prefix /opt/usr --global
      
	      #Remove the temporary entries from /etc/profile
	      sed -i '/opt\/usr\/bin\/node/d' /etc/profile
	      sed -i '/opt\/usr\/bin\/npm/d' /etc/profile
	      source /etc/profile > /dev/null
	      
	      sleep 2
	      
	      echo " "
	      echo "Installation of Node.Js Accomplished ! Now exit and reboot your system !"
	      #ln -s /opt/usr/bin/node /usr/bin/node
	      
	  else
	      echo "/opt is not a valid mount point !"
	      exit 0
	fi
	
}


#-------------------------------CHECK-FOR-FDISK------------------------------------

if [ `which fdisk` ] || [ -x /sbin/fdisk ]
then

#--------------------------------MENU-START----------------------------------------

#if ( [ -d /opt ] && `grep -qs '/opt' /proc/mounts` && `grep -qs '/dev/sda2' /proc/swaps` ) || ( [ -d '/mnt/sda1' ] && `grep -qs '/mnt/sda1' /proc/mounts` && returngigs )
if ( [ -d /opt ] && `grep -qs '/opt' /proc/mounts` && `grep -qs '/dev/sda2' /proc/swaps` ) || ( `ls /dev/ | grep -qs -m 1 sda` && returngigs )

  then
      
      clear
      
      disclaimer
      
      echo ""
      read -p "Press [Enter] key to continue..."
      echo ""
      
      clear
      
      while [ "$done" != "true" ]

      do

      logo
      
      echo "Welcome to Linino Node.Js installation script v13"
      echo ""

      echo "Linino node.js installation menu"
      echo ""
      echo "1. Prepare SDCard and install node.js"
      echo "2. Revert to original settings"
      echo "3. Exit and reboot"
      echo "4. Kill all node processes"
      echo "0. Exit"


      echo " "
      echo "Choose : "
      echo " "

      read scelta

	      case $scelta in
		      #------------------Choice-1----------------------
		      1) 
			  echo " "
			  #-----------INNER-LOOP---------------------------------------------
			  
			  p=1
			  
			  while [ $p != 0 ]

			  do
			  
			      if [ -d '/mnt/sda1' ] && `grep -qs '/mnt/sda1' /proc/mounts`
			      then
			      
				      echo ""
				      echo "WARNING : All data on your SDCard Would will be erased, are you sure ? (y/n)"
				      echo ""
						      
				      read YN
					  
					  case $YN in
						[yY]*) 	
							  echo ""
							  prereqs
							  
							  sleep 2
							  
							  echo ""
							  echo "Erasing all data..."
							  echo ""
							  
							  #Returns the size of the SDCard
							  returngigs
							  
							  #Formats the SDcard according to its size
							  formatsdcard $sizetoformat
							  
							  sleep 5
							  
							  #Updates the system settings
							  system
							  
							  sleep 5
							  
							  #Installs and configures node.js on the board
							  nodejs
							  
 							  sleep 5

							  p=0
						    ;;
						[nN]*) 	
							  echo ""
							  echo "Good Bye for now..."
							  echo ""
							  
							  p=0				    
						    ;;
						    *)
							  echo ""
							  echo "You have to make a choice !"
							  echo ""
						    ;; 
					  esac
					  
			      elif [ -x '/opt/usr/bin/node' ] && `grep -qs '/opt' /proc/mounts`
			      then
				      
				      echo ""
				      echo "Node.js is already installed !"
				      echo ""
				      
				      p=0
				      
			      fi
		      
			  done
			  
		      ;;
		      
		      #----------------- Choice-2---------------------
		      2)  
			  if [ ! -z `which node` ] || [ -x /opt/usr/bin/node ]
			  then
					  
					  echo ""	
					  echo "Reverting to defaults..."
			  		  echo ""
			  		  
					  sleep 2
			  			
			  		  #Removes ideino if installed
					  removeideino
					  
					  sleep 5
					  
					  #Removes node.js
					  opkg update
					  opkg remove node
					  
					  sleep 3
			  		
			  		  #Formats the SDcard to its original state
					  formatvfat

					  sleep 5

					  #Reverts the system settings to the default ones
					  reverttodefault
			  
					  sleep 5

					  #Removes the prerequisites
					  removeprereqs
			  
					  echo ""
					  echo "Reverting complete !"
					  echo ""
					  			  		
					  if [ -d /opt ]
					  then
					  
					      rm -rf /opt
					      
					  fi
				  
			      else
			      
					  echo ""
					  echo "ERROR ! Node.Js is not installed in the system !"
			  		  echo ""

			  fi
			  
			  ;;
			  
		      #------------------Choice-3----------------------
		      3)
			  
			  echo ""
			  echo "Rebooting..."
			  echo ""
			  
			  done="true" && reboot && exit 
			    
		      ;;
		      
		      #------------------Choice-4----------------------
		      4)
			  
			  echo ""
			  echo "Killing all node processes..."
			  echo ""
			  
			  ps www | grep -i [n]ode | grep -v sh | awk {'print $1'} | xargs kill -9 > /dev/null 2>&1
			  
			  sleep 1
			  
			  reset-mcu
		      ;;
		      
		      #------------------Choice-0----------------------
		      0)
			  echo " "
			  echo "Done !"
			  echo " "
			  
			  done="true"
			  exit 0
		      ;;
		      
		      #--------Anychoice---------------------
		      *)
			  echo ""
			  echo "You have to make a choice !"
			  echo ""
		      ;;    
	      esac
	    
      done	      


elif ! `fdisk -l | grep -qs "Disk /dev/sda"` || ( ! `fdisk -l | grep -qs "Disk /dev/sda"` && ! `grep -qs '/opt' df` && ! `blkid | grep -qs "driveSD"` && ! `blkid | grep -qs "swapSD"` ) 

  then
      
	echo ""
	echo "Please insert the SDCard into the board !"
	echo ""

      
elif `fdisk -l | grep -qs "Disk /dev/sda"` && ! `grep -qs '/opt' df` && ( `blkid | grep -qs "driveSD"` && `blkid | grep -qs "swapSD"` ) || ( `blkid | grep -qs "driveSD"` || `blkid | grep -qs "swapSD"` )

  then

	echo ""
	echo "Fixing Node.Js installation..."
	echo ""
  
	swapoff /dev/sda2 > /dev/null 2>&1
	umount /opt > /dev/null 2>&1
	
	sleep 5
	
	/etc/init.d/fstab restart > /dev/null 2>&1

	echo ""
	echo "Node.Js installation FIXED !"
	echo ""

elif [ ! -d '/mnt/sda1' ] || ! `grep -qs '/mnt/sda1' /proc/mounts`

  then

	echo ""
	echo "Can't mount the microSD card, check your system configuration !"
	echo ""
	
fi

#---------------------END-FDISK-CHECK----------------------------------------------

else

    echo ""
    echo "Fdisk is not installed ! ! ! The script will install the package for you..."
    echo ""
  
    read -p "Press [Enter] key to install fdisk..."
    echo ""
    
    sleep 1
    
    #Installing fdisk to the system
    opkg update && opkg install fdisk
    
    echo ""
    echo "Fdisk is now installed ! You have to relaunch the script !"
    echo ""

fi