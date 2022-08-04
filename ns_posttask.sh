#!/bin/bash

env=$1
instnum=$2

### Function usage
usage() {
	  echo "Usage: `basename $0` ARG1 ARG2 ARG3 ARG4"
	  echo "Where:"
	  echo "  ARG1 is the environment name."
	  echo "  ARG2 is the instance number."
}

envlower=$(echo $env| tr '[:upper:]' '[:lower:]')
### Check the parameters
if [[ $envlower == "dev" || $envlower == "qa" || $envlower == "sit" || $envlower == "uat" || $envlower == "prd" || $envlower == "trn" || $envlower == "poc" ]]; then
   echo "Environment provided is: $env"  
else
   echo " ERROR: Environment is not correct or not provided,Please check Usage "; usage; exit 99
fi
if [[ $instnum == 00[1-9] ]]; then
   echo "Instance Number provided is: $instnum"
else
   echo " ERROR: Instance number  is not correct or not provided,Please check Usage "; usage; exit 100
fi

NSNAME=$(echo "iwazu${envlower}ina${instnum}")
SVCNAME=$(oc get service -n $NSNAME |grep mobility|awk '{print $1}')
SVCPORT=$(oc get service -n $NSNAME |grep mobility|awk '{print $5}'|cut -d'/' -f1)
GLP=$(oc get route -n $NSNAME |grep $SVCNAME |awk '{print $3}')
NOW=$(date +%d%m%Y%H%M%S)
mkdir -p /tmp/my-$NOW
BDIR="/tmp/my-$NOW"

### below line for NSNAME is only for tetsing and can be removed later
#NSNAME=$(echo "iwazu${envlower}ina${instnum}")

HOSTDOMAIN=$(oc whoami --show-console | cut -d "." -f2-6)

### Check the evaluated values
if [[ $NSNAME == "" || $SVCNAME == "" || $SVCPORT == "" || $GLP == "" ]]; then echo "Error: One or more required arguments are missing"; exit 101; fi



cat << EOA > $BDIR/gw.yml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: graphql-gateway
  namespace: NSNAME
spec:
  selector:
    istio: ingressgateway
  servers:
  - hosts:
    - NSNAME.HOSTDOMAIN
    port:
      name: https
      number: 443
      protocol: HTTPS
    tls:
      credentialName: iwtls-secret
      mode: SIMPLE
EOA
cat << EOB > $BDIR/vs.yml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: graphql
  namespace: NSNAME
spec:
  gateways:
  - graphql-gateway
  hosts:
  - HOSTROUTE 
  http:
  - match:
    - uri:
        exact: GLP
    route:
    - destination:
        host: SVCNAME
        port:
          number: SVCPORT
EOB
cat << EOC > $BDIR/ra.yml
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: jwt-iw
  namespace: NSNAME
spec:
  jwtRules:
  - forwardOriginalToken: true
    issuer: https://sts.windows.net/60beb100-3973-4346-bd68-d1c4eb6f4c42/
    jwksUri: https://login.microsoftonline.com/common/discovery/keys
    outputPayloadToHeader: x-jwt
  selector:
    matchLabels:
      app: SVCNAME
EOC
cat << EOD > $BDIR/ap.yml
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  creationTimestamp: null
  name: require-jwt-iw
  namespace: NSNAME
spec:
  action: ALLOW
  rules:
  - when:
    - key: request.auth.claims[iss]
      values:
      - https://sts.windows.net/60beb100-3973-4346-bd68-d1c4eb6f4c42/
  - from:
    - source:
        ipBlocks:
        - 10.128.0.0/14
  selector:
    matchLabels:
      app: SVCNAME
EOD

sed "s/NSNAME/$NSNAME/g" $BDIR/gw.yml | sed "s/HOSTDOMAIN/$HOSTDOMAIN/g" |oc apply -f -
HOSTROUTE=$(echo "$NSNAME.$HOSTDOMAIN")
echo $HOSTROUTE

sed "s/NSNAME/$NSNAME/g" $BDIR/vs.yml > $BDIR/vstmp.yml
sed "s/SVCNAME/$SVCNAME/g" $BDIR/vstmp.yml > $BDIR/vstmp1.yml
sed "s/SVCPORT/$SVCPORT/g" $BDIR/vstmp1.yml > $BDIR/vstmp2.yml
sed "s|GLP|$GLP|g" $BDIR/vstmp2.yml > $BDIR/vstmp3.yml
sed "s/HOSTROUTE/$HOSTROUTE/g" $BDIR/vstmp3.yml | oc apply -f -

sed "s/NSNAME/$NSNAME/g" $BDIR/ra.yml | sed "s/SVCNAME/$SVCNAME/g" |oc apply -f -
sed "s/NSNAME/$NSNAME/g" $BDIR/ap.yml | sed "s/SVCNAME/$SVCNAME/g" |oc apply -f -
