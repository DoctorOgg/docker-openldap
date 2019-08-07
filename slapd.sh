#!/bin/bash

status () {
  echo "---> ${@}" >&2
}

convert_fqdn_to_dn(){
  echo ${1}| sed -e 's/^/dc=/' -e 's/\./,dc=/'
}

set_config(){
  echo "Setting CONFIG: ---> ${@}" >&2
  echo "$@" | debconf-set-selections
}

ldap_add_ldif_exteral(){
  status "Adding LDIF: $1"
  ldapadd -Y EXTERNAL -H ldapi:/// -f $1
}

set_cn_config_password(){
  status "setting cn=admin,cn=config password"
  sleep 3
  config_password=`/usr/sbin/slappasswd -s ${1}`
  ldapmodify -Q -Y EXTERNAL -H ldapi:/// << EOF
dn: olcDatabase={0}config,cn=config
changetype: modify
add: olcRootPW
olcRootPW: ${config_password}
EOF
}


disable_anon_binds(){
  status "Disable Anonymous Access"
  ldapmodify -Y EXTERNAL -H ldapi:/// << EOF
dn: cn=config
changetype: modify
add: olcDisallows
olcDisallows: bind_anon
-
add: olcRequires
olcRequires: authc

dn: olcDatabase={-1}frontend,cn=config
changetype: modify
add: olcRequires
olcRequires: authc
EOF
}


add_indexes(){
  status "Adding Indexes"
  ldapmodify -Y EXTERNAL -H ldapi:/// << EOF
dn: olcDatabase={1}mdb,cn=config
changetype: modify
add: olcDbIndex
olcDbIndex: sn pres,sub,eq
-
add: olcDbIndex
olcDbIndex: displayName pres,sub,eq
-
add: olcDbIndex
olcDbIndex: default sub
-
add: olcDbIndex
olcDbIndex: mail,givenName eq,subinitial
-
add: olcDbIndex
olcDbIndex: dc eq
-
add: olcDbIndex
olcDbIndex: uniqueMember eq
EOF
}

# dn: olcDatabase={1}mdb,cn=config

enable_modules(){
  status "Adding Modules"
  ldapadd -Y EXTERNAL -H ldapi:/// << EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: syncprov
-
add: olcModuleLoad
olcModuleLoad: memberof
-
add: olcModuleLoad
olcModuleLoad: refint
-
add: olcModuleLoad
olcModuleLoad: ppolicy
-
add: olcModuleLoad
olcModuleLoad: smbk5pwd
EOF

}

setup_overlays(){
  status "Setting up overlays"
  ldapadd -Y EXTERNAL -H ldapi:/// << EOF
dn: olcOverlay=memberof,olcDatabase={1}mdb,cn=config
objectClass: olcConfig
objectClass: olcMemberOf
objectClass: olcOverlayConfig
objectClass: top
olcOverlay: memberof

dn: olcOverlay=refint,olcDatabase={1}mdb,cn=config
objectClass: olcConfig
objectClass: olcMemberOf
objectClass: olcOverlayConfig
objectClass: top
olcOverlay: refint

dn: olcOverlay=ppolicy,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcPPolicyConfig
olcOverlay: ppolicy
olcPPolicyDefault: cn=Password,ou=Policies,`convert_fqdn_to_dn ${LDAP_DOMAIN}`

dn: olcOverlay=smbk5pwd,olcDatabase={1}mdb,cn=config
objectClass: olcOverlayConfig
objectClass: olcSmbK5PwdConfig
olcOverlay: smbk5pwd
olcSmbK5PwdEnable: samba
olcSmbK5PwdEnable: shadow
olcSmbK5PwdMustChange: 2592000
EOF

}

setup_basic_structure(){

  status "Setting up Password Policy"
  ldapadd -v -x -D "cn=admin,`convert_fqdn_to_dn ${LDAP_DOMAIN}`" -w ${LDAP_ROOTPASS}  -H ldapi:/// << EOF
dn: ou=Policies,`convert_fqdn_to_dn ${LDAP_DOMAIN}`
objectClass: top
objectClass: organizationalUnit
ou: Policies

dn: cn=Password,ou=Policies,`convert_fqdn_to_dn ${LDAP_DOMAIN}`
objectClass: top
objectClass: device
objectClass: pwdPolicy
pwdAttribute: 2.5.4.35
cn: default
pwdMaxAge: 7776002
pwdExpireWarning: 432000
pwdInHistory: 3
pwdCheckQuality: 1
pwdMinLength: 8
pwdMaxFailure: 5
pwdLockout: TRUE
pwdLockoutDuration: 900
pwdGraceAuthNLimit: 0
pwdFailureCountInterval: 0
pwdMustChange: TRUE
pwdAllowUserChange: TRUE
pwdSafeModify: FALSE

dn: ou=People,`convert_fqdn_to_dn ${LDAP_DOMAIN}`
objectClass: top
objectClass: organizationalUnit
ou: People

dn: ou=Groups,`convert_fqdn_to_dn ${LDAP_DOMAIN}`
objectClass: top
objectClass: organizationalUnit
ou: Groups
EOF



}


add_schemas(){

  for schema in  sudo dyngroup openldap collective corba duaconf java misc ppolicy pmi; do
    ldap_add_ldif_exteral /etc/ldap/schema/${schema}.ldif
  done

  for file_schema in `ls /addtional-schemas/*.ldif`; do
    ldap_add_ldif_exteral $file_schema
  done
}

if [ ! -e /var/lib/ldap/docker_bootstrapped ]; then
  status "configuring slapd for first run"
  cp -rv /etc/ldap-skel/* /etc/ldap/
  export DEBIAN_FRONTEND noninteractive

  set_config "slapd	slapd/password2 password ${LDAP_ROOTPASS}"
  set_config "slapd	slapd/internal/adminpw password ${LDAP_ROOTPASS}"
  set_config "slapd	slapd/internal/generated_adminpw password ${LDAP_ROOTPASS}"
  set_config "slapd	slapd/password1 password ${LDAP_ROOTPASS}"
  set_config "slapd	shared/organization	string $LDAP_ORGANISATION"
  set_config "slapd	slapd/domain	string $LDAP_DOMAIN"
  set_config "slapd	slapd/backend	select	MDB"

  dpkg-reconfigure slapd

  status "starting slapd"
  /usr/sbin/slapd -h "ldapi:/// ${LDAP_URLS}" -d ${SLAPD_DEBUG_LEVEL} &
  set_cn_config_password ${LDAP_ROOTPASS}
  disable_anon_binds
  add_schemas
  add_indexes
  enable_modules
  setup_overlays
  setup_basic_structure
  touch /var/lib/ldap/docker_bootstrapped
  wait
else
  status "found already-configured slapd"
  status "starting slapd"
  exec /usr/sbin/slapd -h "ldapi:/// ${LDAP_URLS}" -d ${SLAPD_DEBUG_LEVEL}
fi
