{ writeShellScriptBin
, runCommandCC, openssl, pbkdf2-sha512-src
, writeShellApplication, cryptsetup, yubikey-personalization
}:

rec {
  hextorb = writeShellScriptBin "hextorb" ''
    tr '[:lower:]' '[:upper:]' | sed -e 's/\([0-9A-F]\{2\}\)/\\\\\\x\1/gI' | xargs printf
  '';

  rbtohex = writeShellScriptBin "rbtohex" ''
    od -An -vtx1 | tr -d ' \n'
  '';

  pbkdf2-sha512 = runCommandCC "pbkdf2-sha512" { buildInputs = [ openssl ]; } ''
    $CC -O3 \
      -I${openssl.dev}/include \
      -L${openssl.out}/lib \
      ${pbkdf2-sha512-src} \
      -o pbkdf2-sha512 -lcrypto

    install -TD pbkdf2-sha512 $out/bin/pbkdf2-sha512
  '';

  luks-setup = writeShellApplication {
    name = "luks-setup";

    runtimeInputs = [
      hextorb
      rbtohex
      pbkdf2-sha512

      cryptsetup
      openssl
      yubikey-personalization
    ];

    text = ''
      printHelp() {
        echo 'Usage: luks-setup [-h] (--luks-part | -l <path>) (--efi-part | -e <path>)'
        echo '                  [--efi-mnt | -m <path>] [--password | -p]'
        echo '                  [--salt | -s <number>] [--storage | -S <path>]'
        echo '                  [--key | -k <number>] [--iterations | -i <number>]'
        echo '                  [--cipher | -c <name>] [--hash | -h <name>]'
        echo 'Unlock a YubiKey-secured LUKS device'
        echo ""
        echo 'Options:'
        echo '  -c  --cipher         Cipher to use (default: aes-xts-plain64)'
        echo '  -e  --efi-part       EFI System Partition'
        echo '  -h  --help           Print this message and exit'
        echo '  -H  --hash           Hash algorith to use (default: sha512)'
        echo '  -i  --iterations     PBKDF2 iterations (default: 1000000)'
        echo '  -k  --key            Key length in bits (default: 512)'
        echo '  -l  --luks-part      LUKS device partition'
        echo '  -m  --efi-mnt        ESP mount point (default: /root/boot)'
        echo '  -p  --password       Whether password 2FA is enabled'
        echo '  -s  --salt           Salt length in bits (default: 16)'
        echo '  -S  --storage        Location of the salt storage relative to the ESP (default: /crypt-storage/default)'
      }

      SALT_LENGTH=16
      KEY_LENGTH=512
      ITERATIONS=1000000

      EFI_PART=
      LUKS_PART=
      EFI_MNT=/root/boot
      STORAGE=/crypt-storage/default
      CIPHER=aes-xts-plain64
      HASH=sha512
      salt=

      withPassword=

      while [ "$#" -gt 0 ]; do
          i="$1"; shift 1
          case "$i" in
            --cipher|-c)
              CIPHER="$1"
              shift 1
              ;;
            --efi-part|-e)
              EFI_PART="$1"
              shift 1
              ;;
            --help|-h)
              printHelp
              exit 0
              ;;
            --hash|-H)
              HASH="$1"
              ;;
            --iterations|-i)
              ITERATIONS="$1"
              shift 1
              ;;
            --key|-k)
              KEY_LENGTH="$1"
              shift 1
              ;;
            --luks-part|-l)
              LUKS_PART="$1"
              shift 1
              ;;
            --efi-mnt|-m)
              EFI_MNT="$1"
              shift 1
              ;;
            --password|-p)
              withPassword=1
              ;;
            --salt|-s)
              SALT_LENGTH="$1"
              shift 1
              ;;
            --storage|-S)
              STORAGE="$1"
              shift 1
              ;;
            *)
              echo "$0: unknown option \`$i'"
              exit 1
              ;;
          esac
      done

      if [[ -z "$LUKS_PART" ]]; then
        echo 'error: LUKS partition required'
        exit 1
      elif [[ -z "$EFI_PART" ]]; then
        echo 'error: EFI System Partition required'
        exit 1
      fi

      salt="$(dd if=/dev/urandom bs=1 count="$SALT_LENGTH" 2>/dev/null | rbtohex)"
      challenge="$(echo -n "$salt" | openssl dgst -binary -sha512 | rbtohex)"
      response="$(ykchalresp -2 -x "$challenge" 2>/dev/null)"

      if [[ -z "$response" ]]; then
        echo 'Failed to compute response. Please check your YubiKey.'
        exit 1
      fi

      if [[ -n "$withPassword" ]]; then
        echo -n 'Enter password: '
        read -r -s k_user
        k_luks="$(echo -n "$k_user" | pbkdf2-sha512 $((KEY_LENGTH / 8)) "$ITERATIONS" "$response" | rbtohex)"
      else
        k_luks="$(echo | pbkdf2-sha512 $((KEY_LENGTH / 8)) "$ITERATIONS" "$response" | rbtohex)"
      fi

      mkdir -p "$EFI_MNT"
      mkfs.vfat -F 32 -n uefi "$EFI_PART"
      mount "$EFI_PART" "$EFI_MNT"
      mkdir -p "$(dirname "$EFI_MNT$STORAGE")"
      echo -ne "$salt\n$ITERATIONS" > "$EFI_MNT$STORAGE"
      echo -n "$k_luks" | hextorb | cryptsetup luksFormat --cipher="$CIPHER" --key-size="$KEY_LENGTH" --hash="$HASH" --key-file=- "$LUKS_PART"

      if [[ "$?" -eq 1 ]]; then
        echo 'Failed to set up volume'
        exit 1
      fi
    '';
  };

  luks-unlock = writeShellApplication {
    name = "luks-unlock";

    runtimeInputs = [
      hextorb
      pbkdf2-sha512
      rbtohex

      cryptsetup
      openssl
    ];

    text = ''
      printHelp() {
        echo 'Usage: luks-unlock [-h] [--efi-mnt | -m <path>] [--luks-part | -l <path>]'
        echo '                   [--luks-root | -l <name>] [--password | -p]'
        echo '                   [--key | -k <number>] [--slot | -s (1 | 2)]'
        echo '                   [--abs-storage | -a <path>] [--storage | -S <path>]'
        echo 'Unlock a YubiKey-secured LUKS device'
        echo ""
        echo 'Options:'
        echo '  -a  --abs-storage    Location of the salt storage'
        echo '  -h  --help           Print this message and exit'
        echo '  -k  --key            Key length in bits (default: 512)'
        echo '  -l  --luks-part      LUKS device partition'
        echo '  -m  --efi-mnt        ESP mount point (default: /root/boot)'
        echo '  -p  --password       Whether password 2FA is enabled'
        echo '  -r  --luks-root      Name of the unencrypted device (default: nixos-enc)'
        echo '  -s  --slot           The YubiKey slot to challenge (default: 2)'
        echo '  -S  --storage        Location of the salt storage relative to the ESP (default: /crypt-storage/default)'
      }

      SLOT=2
      STORAGE=/crypt-storage/default
      EFI_MNT=/root/boot
      LUKSROOT=nixos-enc
      KEY_LENGTH=512
      ITERATIONS=
      salt=

      ABS_STORAGE=
      withPassword=

      while [ "$#" -gt 0 ]; do
          i="$1"; shift 1
          case "$i" in
            --abs-storage|-a)
              ABS_STORAGE="$1"
              shift 1
              ;;
            --help|-h)
              printHelp
              exit 0
              ;;
            --key|-k)
              KEY_LENGTH="$1"
              shift 1
              ;;
            --luks-part|-l)
              LUKS_PART="$1"
              shift 1
              ;;
            --efi-mnt|-m)
              EFI_MNT="$1"
              shift 1
              ;;
            --password|-p)
              withPassword=1
              ;;
            --luks-root|-r)
              LUKSROOT="$1"
              shift 1
              ;;
            --slot|-s)
              SLOT="$1"
              shift 1
              ;;
            --storage|-S)
              STORAGE="$1"
              shift 1
              ;;
            *)
              echo "$0: unknown option \`$i'"
              exit 1
              ;;
          esac
      done

      if [[ -z "$LUKS_PART" ]]; then
        echo 'error: LUKS partition required'
        exit 1
      fi

      if [[ -n "$ABS_STORAGE" ]]; then
        salt="$(awk 'NR==1 {printf "%s", $1}' "$ABS_STORAGE")"
        ITERATIONS="$(awk 'NR==2 {printf "%s", $1}' "$ABS_STORAGE")"
      else
        salt="$(awk 'NR==1 {printf "%s", $1}' "$EFI_MNT$STORAGE")"
        ITERATIONS="$(awk 'NR==2 {printf "%s", $1}' "$EFI_MNT$STORAGE")"
      fi

      if [[ -z "$salt" ]]; then
        echo 'error: No salt found'
        exit 1
      elif [[ -z "$ITERATIONS" ]]; then
        echo 'error: No iterations count found'
        exit 1
      fi

      challenge="$(echo -n "$salt" | openssl dgst -binary -sha512 | rbtohex)"
      response="$(ykchalresp -"$SLOT" -x "$challenge" 2>/dev/null)"

      if [[ -n "$withPassword" ]]; then
        echo -n 'Enter password: '
        read -r -s k_user
        k_luks="$(echo -n "$k_user" | pbkdf2-sha512 $((KEY_LENGTH / 8)) "$ITERATIONS" "$response" | rbtohex)"
      else
        k_luks="$(echo | pbkdf2-sha512 $((KEY_LENGTH / 8)) "$ITERATIONS" "$response" | rbtohex)"
      fi

      echo -n "$k_luks" | hextorb | cryptsetup luksOpen "$LUKS_PART" "$LUKSROOT" --key-file=-

      if [[ "$?" -eq 1 ]]; then
        echo 'Failed to unlock volume'
        exit 1
      fi

      echo "Unencrypted volume at /dev/mapper/$LUKSROOT"
    '';
  };
}
