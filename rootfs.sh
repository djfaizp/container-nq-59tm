#!/bin/sh -e 
##!! PLEASE USE THIS SCRIPT WITH CAUTION - AND AT YOUR OWN RISK          !!##
##!! IT HAS BEEN KNOWN TO CAUSE RESETS AND WIPE DATA ON SOME CHROMEBOXES !!##

APPLICATION="${0##*/}"
ANSWER=''
SUDO=''

USAGE="
$APPLICATION [no options]

### A script that asks the user to make the root filesystem
##+ read-writable for subsequent changes and additions by the user. 
"

## Exits the script with exit code $1, spitting out message $@ to stderr
error() {
  local ecode="$1"
  shift
  echo "$*" 1>&2
  exit "$ecode"
}

if [ $# -gt 0 ]; then error 0 "$USAGE"; fi

## Check for bootcache fix ...
checkbootcache () {
  ret=$(grep -iq bootcache /usr/share/vboot/bin/make_dev_ssd.sh; echo $?)
  if [ $ret -gt 0 ];
  then echo "$ret: No 'bootcache' fix appplied yet. :("
    echo "Not safe to continue, exiting..."
    exit $ret
  else echo "$ret: The 'bootcache' fix has been appplied - yay. :)"
    echo "You can now run 'rw-rootfs' safely."
  fi
}

## Report dev_boot_legacy and dev_boot_usb flags
## Check and set dev_boot_signed_only flag if needed.
checkflags() {
  boot="$($SUDO crossystem dev_boot_usb dev_boot_legacy dev_boot_signed_only)"
  echo -n "## "
  echo "$boot"
  echo " ##"
  # db_usb and db_legacy can be off, db_signed_only should be off.
  echo "$boot" | {
    read -r usb legacy signed
    suggest=''
    if [ "$usb" = 1 ]; then
      echo "NOTE: USB booting <Ctrl+U> is enabled." 1>&2
    else
      echo "WARNING: USB booting is disabled." 1>&2
      suggest="$suggest dev_boot_usb=1"
    fi
    if [ "$legacy" = 1 ]; then
      echo "NOTE: Legacy booting <Ctrl+L> is enabled." 1>&2
    else
      echo "WARNING: Legacy booting is disabled." 1>&2
      suggest="$suggest dev_boot_legacy=1"
    fi
    if [ -n "$suggest" ]; then
      echo "To enable, you can use the following command: $SUDO crossystem$suggest" 1>&2
      sleep 3
    fi
    if [ "$signed" = 1 ]; then
      # Only disable signed booting if the user hasn't to ensure booting unverified kernels
      echo "WARNING: Signed boot verification is enabled; disabling it to ensure booting unverified kernel." 1>&2
      echo "You can enable it again using: $SUDO crossystem dev_boot_signed_only=1" 1>&2
      $SUDO crossystem dev_boot_signed_only=0 || true
      sleep 3
    else
      echo "NOTE: Signed boot verification is disabled, you're good to go..." 1>&2
    fi
    sleep 2
  } 
}

##
## If we're not running as root, restart as root.
if [ ${UID:-$(id -u)} -ne 0 ]; then
  echo "...elevating $USER to superuser via 'sudo'..."
  SUDO='sudo'
fi

if $SUDO mount -i -o remount,rw / 2>/dev/null; then
  echo "*** $(mount | grep ' / ') ***"
  error 0 "Your rootfs is already mounted read-write ..."
fi

echo -n "Perform  REMOVAL of rootfs verification (Y/n/q) ? " 1>&2
read ANSWER
case ${ANSWER:-y} in
  [yY]*) checkbootcache 
         checkflags 
         echo
         if grep -q CHROMEOS_RELEASE_BOARD=chromeover64 /etc/lsb-release 
         then
             echo "...using CloudReady, disabling verity."
	     echo "$SUDO disable_verity" 1>&2
	     $SUDO disable_verity || ret=$? || true
         else
             echo "$SUDO /usr/libexec/debugd/helpers/dev_features_rootfs_verification" 1>&2
                   $SUDO /usr/libexec/debugd/helpers/dev_features_rootfs_verification || ret=$?
	 fi
         if [ $ret -gt 0 ]; then
             error 2 "Sorry but REMOVAL of rootfs verification failed."
         else
	     echo
             echo "*** Rebooting in 10 seconds to make changes effective ***" 1>&2
             read -t 10 -p "... ENTER 'a' TO ABORT! " GO
             if [ -n "${GO}" ]; then error 0 "Okay, ABORTING ..."; fi
             $SUDO reboot && exit $ret
         fi
      ;;
  [nN]*) error 0 "Skipping REMOVAL of rootfs verification for now..."
      ;;
  [qQ]*) error 0 "Quitting - no changes made..."
      ;;
  *)     error 1 "Not a valid choice, exiting..."
      ;;
esac
