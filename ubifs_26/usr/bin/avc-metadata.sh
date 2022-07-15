#!/bin/sh
. /lib/functions.sh

# Usage: 
	# Place this file avc-metadata.sh  at /usr/bin/avc-metadata.sh.
	# Run below command to generate avc metadata xml file(filename given as argument 1)
	# avc-metadata.sh /etc/confd/cdb/avc-meta-data_init.xml

#/etc/confd/cdb/avc-meta-data_init.xml
CDBFILEPATH=/tmp
AVCMETADATADEFFILENAME=$CDBFILEPATH/avc-meta-data_init.xml

category_fun() {
  local name=$1

  echo "      <category>" >> $AVCMETADATAFILENAME
  config_get val "$name" id
  echo "        <id>$val</id>" >> $AVCMETADATAFILENAME

  echo "        <applications>" >> $AVCMETADATAFILENAME
  config_list_foreach "$name" application handle_application
  echo "        </applications>" >> $AVCMETADATAFILENAME
  config_get p "$name" parent
  echo "        <parent>$p</parent>" >> $AVCMETADATAFILENAME

  config_get val "$name" name 
  x=`echo $val | sed "s/\&/\&amp;/g"`
  echo "        <name>$x</name>" >> $AVCMETADATAFILENAME

  config_get d "$name" description 
  echo "        <description>$d</description>" >> $AVCMETADATAFILENAME

  echo "      </category>" >> $AVCMETADATAFILENAME
}

group_fun() {
  local name=$1

  echo "      <group>" >> $AVCMETADATAFILENAME

  config_get val "$name" id
  echo "        <id>$val</id>" >> $AVCMETADATAFILENAME    

  config_get val "$name" name
  x=`echo $val | sed "s/\&/\&amp;/g"`      
  echo "        <name>$x</name>" >> $AVCMETADATAFILENAME
  echo "        <categories>" >> $AVCMETADATAFILENAME
  config_list_foreach "$name" category handle_category
  echo "        </categories>" >> $AVCMETADATAFILENAME

  echo "      </group>" >> $AVCMETADATAFILENAME
}

application_fun() {
  local name=$1

  echo "      <application>" >> $AVCMETADATAFILENAME
  config_get val "$name" id
  echo "        <id>$val</id>" >> $AVCMETADATAFILENAME
  
  config_get val "$name" name 
  x=`echo $val | sed "s/\&/\&amp;/g"`      
  echo "        <name>$x</name>" >> $AVCMETADATAFILENAME
  config_list_foreach "$name" behaviour handle_behaviour

  echo "      </application>" >> $AVCMETADATAFILENAME
}

behaviour_fun() {
  local name=$1
  echo "      <behaviour>" >> $AVCMETADATAFILENAME
  config_get val "$name" id
  echo "        <id>$val</id>">> $AVCMETADATAFILENAME
  
  config_get val "$name" name 
  x=`echo $val | sed "s/\&/\&amp;/g"`      
  echo "        <name>$x</name>" >> $AVCMETADATAFILENAME
  echo "        <description></description>">> $AVCMETADATAFILENAME

  echo "      </behaviour>" >> $AVCMETADATAFILENAME
}

handle_application() {
  echo "          <application>$1</application>" >> $AVCMETADATAFILENAME
}

handle_category() {
  echo "          <categores>$1</categores>" >> $AVCMETADATAFILENAME
}

handle_behaviour() {
  echo "        <behaviors>$1</behaviors>" >> $AVCMETADATAFILENAME
}

create_avc_metadata_xml_file() {
# $1, argument 1(input): UCI module/file name from which application mapping can be read

  local appuciname=$1

  rm -f $AVCMETADATAFILENAME
  echo "<config xmlns=\"http://tail-f.com/ns/config/1.0\">" > $AVCMETADATAFILENAME
  #echo "  <avc-meta-data xmlns=\"urn:ciscosb:params:xml:ns:yang:ciscosb-security-common\">" >> $AVCMETADATAFILENAME
  echo "  <avc-meta-data xmlns=\"http://cisco.com/ns/ciscosb/security-common\">" >> $AVCMETADATAFILENAME

  config_load $appuciname

  echo "    <categories>" >> $AVCMETADATAFILENAME
  config_foreach category_fun category $appuciname
  echo "    </categories>" >> $AVCMETADATAFILENAME

  echo "    <groups>" >> $AVCMETADATAFILENAME
  config_foreach group_fun group $appuciname 
  echo "    </groups>" >> $AVCMETADATAFILENAME
  
  echo "    <applications>" >> $AVCMETADATAFILENAME
  config_foreach application_fun application $appuciname
  echo "    </applications>" >> $AVCMETADATAFILENAME

  echo "    <behaviours>" >> $AVCMETADATAFILENAME
  config_foreach behaviour_fun behaviour $appuciname
  echo "    </behaviours>" >> $AVCMETADATAFILENAME

  echo "  </avc-meta-data>" >> $AVCMETADATAFILENAME
  echo "</config>" >> $AVCMETADATAFILENAME
}

AVCMETADATAFILENAME=$AVCMETADATADEFFILENAME
if [ "$1" != "" ]; then
  AVCMETADATAFILENAME=$1
fi

create_avc_metadata_xml_file application
