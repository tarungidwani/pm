set -o errexit
set -o pipefail
set -o nounset
# Uncomment line below for debugging purposes
#set -o xtrace

prog_name=$(basename $0)
subcommand=${1-}
secret_name="${2-}"

sub_help(){
    printf "Usage: $prog_name <subcommand> [options]\n\n"
    printf "Subcommands:\n\n"
    printf "\tinit\n"
    printf "\tstatus\n"
    printf "\tunlock\n"
    printf "\tlock\n"
    printf "\tlist\n"
    printf "\tcreate\n"
    printf "\tget\n"
    printf "\tdelete\n"
    printf "\trotate\n"
    printf "\nFor help with each subcommand run:"
    printf "$prog_name <subcommand> -h|--help\n\n"
}

PM_DIR=$HOME/.pm
VAULT=$PM_DIR/.vault
ENCRYPTED_VAULT=$VAULT.gpg

is_vault_locked() {
    # checks whether pm vault exists and is in locked state
    if ([ -f "$ENCRYPTED_VAULT" ] && [ ! -f "$VAULT" ]); then
        echo true
    else
        echo false
    fi
    return 0
}

validate_vault_generic_operation() {

    if ([ $(is_vault_locked) = true ]); then
        printf 'Error: pm vault is locked. Run pm unlock to unlock vault before performing operations.\n' >&2
        return 1
    fi
    return 0
}

validate_vault_targeted_operation() {
    secret_name="${1-}"

    validate_vault_generic_operation

    if ([ $? -ne 0 ]); then
        return 1
    elif ([ -z $secret_name ]); then
        printf 'Error: missing secret name. Specify secret name after the command.\n' >&2
        return 1
    fi
    return 0
}

gen_secure_password() {
    printf "$(openssl rand -base64 64 | tr -d '\n')"
    return 0
}

init() {
    # checks whether pm VAULT has already been initialized
    if ([ -d "$PM_DIR" ]); then
        printf 'pm VAULT already exists\n' >&2
        return 1
    fi

    # Initializes an empty pm vault
    mkdir -m700 "$PM_DIR"
    touch "$VAULT" && chmod 400 "$VAULT"
    gpg -c "$VAULT" && chmod 000 "$ENCRYPTED_VAULT"
    chmod 600 "$VAULT" && shred -zu -n 50 "$VAULT"

    # Restart the gpg agent to flush the cached encryption password in keyring
    echo RELOADAGENT | gpg-connect-agent

    return 0
}

status() {
    if ([ $(is_vault_locked) = true ]); then
        echo 'locked'
    else
        echo 'unlocked'
    fi
}

unlock() {
    # if the pm vault is locked, decrypt the encrypted vault
    # unset permissions for the unlocked vault
    # destroy the encrypted vault
    if ([ $(is_vault_locked) = true ]); then
        chmod 400 "$ENCRYPTED_VAULT" && gpg "$ENCRYPTED_VAULT"
        chmod 000 "$VAULT"
        chmod 600 "$ENCRYPTED_VAULT" && shred -zu -n 50 "$ENCRYPTED_VAULT"
    fi
    # Restart the gpg agent to flush the cached encryption password in keyring
    echo RELOADAGENT | gpg-connect-agent
    return 0
}

lock() {
    # if the pm vault is unlocked, encrypt the unlocked vault
    # unset permissions for the locked vault
    # destroy the unencrypted vault
    if ([ $(is_vault_locked) = false ]); then
        chmod 400 "$VAULT" && gpg -c "$VAULT"
        chmod 000 "$ENCRYPTED_VAULT"
        chmod 600 "$VAULT" && shred -zu -n 50 "$VAULT"
    fi
    # Restart the gpg agent to flush the cached encryption password in keyring
    echo RELOADAGENT | gpg-connect-agent
    return 0
}

list() {
    validate_vault_generic_operation
    if [ $? = 0 ]; then
        chmod 400 $VAULT && echo "$(cut -d' ' -f1 $VAULT)"
        chmod 000 $VAULT
        return 0
    fi
    return 1
}

create() {
    secret_name="${1-}"
    validate_vault_targeted_operation $secret_name

    if [ $? = 0 ]; then
        chmod 400 $VAULT
        if [ $(grep "^$secret_name " $VAULT | wc -l) -eq 0 ]; then
            chmod 600 $VAULT && echo "$secret_name $(gen_secure_password)" >> $VAULT
            chmod 000 $VAULT
            return 0
        fi
        chmod 000 $VAULT
        return 0
    fi
    return 1
}

get() {
    secret_name="${1-}"
    validate_vault_targeted_operation $secret_name
    if [ $? = 0 ]; then
        chmod 400 $VAULT && echo "$(grep "^$secret_name[[:space:]]" $VAULT)"
        chmod 000 $VAULT
        return 0
    fi
    return 1
}

delete() {
    secret_name="${1-}"
    validate_vault_targeted_operation $secret_name
    if [ $? = 0 ]; then
        chmod 600 $VAULT && sed -i "/^$secret_name /d" $VAULT
        chmod 000 $VAULT
        return 0
    fi
    return 1
}

rotate() {
    secret_name="${1-}"
    validate_vault_targeted_operation $secret_name
    if [ $? = 0 ]; then
        secret_value=$(gen_secure_password)
        chmod 600 $VAULT && sed -i "s~^$secret_name .*~$secret_name $secret_value~g" $VAULT
        chmod 000 $VAULT
        return 0
    fi
    return 1
}

case $subcommand in
    "" | "-h" | "--help")
        sub_help
        ;;

    "init")
        init
        ;;
    "status")
        vault_status=$(status)
        printf "$vault_status\n"
        ;;
    "unlock")
        unlock
        ;;
    "lock")
        lock
        ;;
    "list")
        secret_names=$(list)
        if [ ! -z "$secret_names" ]; then
            printf "$secret_names\n"
        fi
        ;;
    "create")
        create $secret_name
        ;;
    "get")
        secret=$(get "$secret_name")
        if [ ! -z "$secret" ]; then
            printf "$secret\n"
        fi
        ;;
    "delete")
        delete $secret_name
        ;;
    "rotate")
        rotate $secret_name
        ;;
    *)
        printf "Error: '$subcommand' is not a known subcommand.\n" >&2
        printf "       Run '$prog_name --help' for a list of known subcommands.\n" >&2
        exit 1
        ;;
esac

exit $?

