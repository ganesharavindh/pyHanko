#!/bin/bash

# Utilities to load the result of the ca-setup.sh script into 
# a PKCS#11 token (intended to be used with something like
# SoftHSMv2, but in theory a hardware token should work too)

set -e


CA_BASEDIR="pyhanko_tests/data/crypto/testing-ca"
TOKEN_NAME=testrsa
#CA_BASEDIR="pyhanko_tests/data/crypto/testing-ca-ecdsa"
#TOKEN_NAME=testecdsa
SLOT_IX=0

if [[ -z "$1" ]] ; then
    echo "Usage: pkcs11-setup.sh MODULE"
    exit 1
fi

MODULE=$1
TOOL="pkcs11-tool --module $MODULE --slot-index $SLOT_IX"


USER_PIN=1234
SO_PIN=5678
DUMMY_PASSWORD=secret
WITH_EXTRA_SIGNER=no


# NOTE: This script assumes the token already exists,
#  since slot indexes and IDs aren't stable until then in SoftHSMv2

init_token () {
     $TOOL --label "$TOKEN_NAME" --so-pin "$SO_PIN" --init-token \
        --init-pin --pin "$USER_PIN"
}

# init_token
# exit



TEMPDIR=$(mktemp -d)

cleanup () {
    find "$TEMPDIR" -type f -name '*.der' -delete
    rmdir "$TEMPDIR"
}

trap cleanup EXIT


KEYDIR="$CA_BASEDIR/keys"

# function to save a key pair in pkcs8 format
# (assumes the passphrase is "secret")
transcode_key () {
    openssl pkcs8 -topk8 -inform pem -outform der \
        -in "$KEYDIR/$1.key.pem" -out "$TEMPDIR/$1.key.der" \
        -passin "pass:$DUMMY_PASSWORD" -nocrypt
}


transcode_cert () {
    openssl x509 -inform pem -outform der \
        -in "$CA_BASEDIR/$1.cert.pem" -out "$TEMPDIR/$2.cert.der"
}

import_key () {
    $TOOL -l --pin "$USER_PIN" --write-object "$TEMPDIR/$1.key.der" \
        --type privkey --label $1 --id $2
}

import_cert () {
    $TOOL -l --pin "$USER_PIN" --write-object "$TEMPDIR/$1.cert.der" \
        --type cert --label $1 --id $2
}


# Import signer cert
transcode_key signer
transcode_cert intermediate/newcerts/signer signer
import_key signer 01
import_cert signer 02


if [[ "$WITH_EXTRA_SIGNER" = yes ]] ; then
    # Import  signer2 cert
    transcode_key signer2
    transcode_cert intermediate/newcerts/signer2 signer2
    import_key signer2 11
    import_cert signer2 12
fi


# import root CA cert
transcode_cert root/certs/ca root
import_cert root 21


# import intermediate CA cert
transcode_cert intermediate/certs/ca intermediate
import_cert intermediate 31
