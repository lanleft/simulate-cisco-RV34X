#!/bin/sh

errcode=1                                                                                                   
errstring="Invalid Arguments"

AAA_USERS="/ciscosb-aaa-trans:aaa/authentication/users"
VERBOSE=0

adduser()
{
	name="$1"
	password="$2"
	group="$3"
	debug=""
	
	[ $VERBOSE -eq 1 ] && debug="-dd"

	ret="`confd_cmd $debug -c "mexists $AAA_USERS/user{$name}"`"

	[ "x$ret" = "xno" ] && {
		confd_cmd $debug -c \
		"mcreate $AAA_USERS/user{$name}; \
		 mset $AAA_USERS/user{$name}/password $password; \
		 mset $AAA_USERS/user{$name}/group $group"
		 
	} || {
		confd_cmd $debug -c \
		"mset $AAA_USERS/user{$name}/password $password; \
		 mset $AAA_USERS/user{$name}/group $group"
	}
	
	echo "$?"
}

deluser()
{
	name="$1"
	debug=""

	[ $VERBOSE -eq 1 ] && debug="-dd"
	
	ret="`confd_cmd $debug -c "mexists $AAA_USERS/user{$name}"`"

	[ "x$ret" = "xyes" ] && {
		confd_cmd $debug -c "mdel $AAA_USERS/user{$name}"
	}
	
	echo "$?"
}

setuser()
{
	name="$1"
	password="$2"
	group="$3"
	debug=""
	
	[ $VERBOSE -eq 1 ] && debug="-dd"
	
	ret="`confd_cmd $debug -c "mexists $AAA_USERS/user{$name}"`"

	[ "x$ret" = "xyes" ] && {
		[ -n "$password" ] && {
			confd_cmd $debug -c "mset $AAA_USERS/user{$name}/password $password;"
			echo "$?"
		}
		
		[ -n "$group" ] && {
			confd_cmd $debug -c "mset $AAA_USERS/user{$name}/group $group;"
			echo "$?"			
		}
	}	
}
case "$1" in
	add)
		shift;
		
		username=""
		password=""
		group=""
		
		while [ -n "$1" ]; do
			case "$1" in
				-u|--username) username="$2"; shift; ;;
				-p|--password) password="$2"; shift; ;;
				-g|--group) group="$2"; shift; ;;
				-v) VERBOSE=1;;
				*) break ;;
			esac
			shift;
		done
		
		[ -n "$username" -a -n "$password" -a -n "$group" ] && {
			adduser "$username" "$password" "$group"
		}
	;;
	del)
		shift;
		
		username=""
		
		while [ -n "$1" ]; do
			case "$1" in
				-u|--username) username="$2"; shift; ;;
				-v) VERBOSE=1;;
				*) break ;;
			esac
			shift;
		done
		
		[ -n "$username" ] && {
			deluser "$username"
		}
	;;
	set)
		shift;
		
		username=""
		password=""
		group=""
		
		while [ -n "$1" ]; do
			case "$1" in
				-u|--username) username="$2"; shift; ;;
				-p|--password) password="$2"; shift; ;;
				-g|--group) group="$2"; shift; ;;
				-v) VERBOSE=1;;
				*) break ;;
			esac
			shift;
		done
		
		[ -n "$username" ] && {
			[ -n "$password" -o -n "$group" ] && {
				setuser "$username" "$password" "$group"
			}
		}
	;;
	*)
		
	;;
esac


