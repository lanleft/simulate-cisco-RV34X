#!/bin/sh
. /lib/functions.sh

# Usage: 
	# Place this file avc-deviceos-metadata.sh  at /usr/bin/avc-deviceos-metadata.sh.
	# Run below command to generate avc deviceos metadata xml file(filename given as argument 1)
	# avc-deviceos-metadata.sh /etc/confd/cdb/device-os-types_init.xml

CDBFILEPATH=/tmp
AVCMETADATADEFFILENAME=$CDBFILEPATH/device-os-types_init.xml

devostype_fun() {
  local name=$1

  if [ "$name" = "ANY" ]; then
    return
  fi

  echo "   <device-os-type>" >> $AVCDEVOSTYPESMETADATAFILENAME

  echo "     <device-type>$name</device-type>" >> $AVCDEVOSTYPESMETADATAFILENAME
  config_list_foreach "$name" os handle_ostype

  echo "   </device-os-type>" >> $AVCDEVOSTYPESMETADATAFILENAME
}

handle_ostype() {
  echo "     <os-type>$1</os-type>" >> $AVCDEVOSTYPESMETADATAFILENAME
}

create_avc_deviceos_metadata_xml_file() {
# $1, argument 1(input): UCI module/file name from which application mapping can be read

  local appuciname=$1

  rm -f $AVCDEVOSTYPESMETADATAFILENAME
  echo "<config xmlns=\"http://tail-f.com/ns/config/1.0\">" > $AVCDEVOSTYPESMETADATAFILENAME
  #echo "  <device-os-types xmlns=\"urn:ciscosb:params:xml:ns:yang:ciscosb-security-common\">" >> $AVCDEVOSTYPESMETADATAFILENAME
  echo "  <device-os-types xmlns=\"http://cisco.com/ns/ciscosb/security-common\">" >> $AVCDEVOSTYPESMETADATAFILENAME

  config_load $appuciname

  add_ANYdev
  config_foreach devostype_fun type $appuciname

  echo "  </device-os-types>" >> $AVCDEVOSTYPESMETADATAFILENAME
  echo "</config>" >> $AVCDEVOSTYPESMETADATAFILENAME
}
add_ANYdev() {

  echo "   <device-os-type>" >> $AVCDEVOSTYPESMETADATAFILENAME
  
  echo "     <device-type>ANY</device-type>" >> $AVCDEVOSTYPESMETADATAFILENAME
  local Alldev=`uci show device | grep "os=" | cut -f 2 -d = | awk '{printf $0 " ";}' | sed 's/ /\n/g' | awk '!seen[$0]++'`
  for devname in $Alldev
  do
    handle_ostype $devname                         
  done

  echo "   </device-os-type>" >> $AVCDEVOSTYPESMETADATAFILENAME
}
AVCDEVOSTYPESMETADATAFILENAME=$AVCMETADATADEFFILENAME
if [ "$1" != "" ]; then
  AVCDEVOSTYPESMETADATAFILENAME=$1
fi

create_avc_deviceos_metadata_xml_file device 
