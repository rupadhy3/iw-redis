#!/bin/bash

env=$1
instnum=$2
kvname=$3
NOW=$(date +%d%m%Y%H%M%S)
mkdir -p /tmp/my-$NOW
BDIR="/tmp/my-$NOW"

acruser=$(az keyvault secret show --name acrUser --vault-name=$kvname)
acrpas=$(az keyvault secret show --name acrPasswd --vault-name=$kvname)

### Function usage
usage() {
  echo "Usage: basename $0 ARG1 ARG2 ARG3"
  echo "Where:"
  echo "  ARG1 is the three letter environment, as dev, qa, sit, uat, prd, trn"
  echo "  ARG2 is the instance number, as 001 to 009."
  echo "  ARG3 is the keyvault name for the environment (NPD or PRD)."
}

### Check the parameters
acruserlower=$(echo $acruser| tr '[:upper:]' '[:lower:]')
acruserupper=$(echo $acruser| tr '[:lower:]' '[:upper:]')
envlower=$(echo $env| tr '[:upper:]' '[:lower:]')
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
if [[ $kvname != "" ]]; then 
  echo "Azure container registry name is: $kvname"
else
  echo " ERROR: Azure container registry name is not correct or not provided,Please check Usage "; usage; exit 101 
fi


NSNAME=$(echo "iwazu${envlower}ina${instnum}")

cat << EOA > $BDIR/ns.yml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: NSNAME
  name: NSNAME
EOA

sed "s/NSNAME/$NSNAME/g" $BDIR/ns.yml  |oc apply -f -

### Adding NS to istio smmr - begin
oc -n istio-system get smmr default -o yaml > /tmp/smmr.yaml
sed -n '1,/^status/p' /tmp/smmr.yaml |sed '/^status/d' > /tmp/smmr1.yaml
cat /tmp/smmr1.yaml | grep -w 'members:' > /dev/null
if [ $? != 0 ]; then
  sed "s/spec: .*/spec: /" /tmp/smmr1.yaml > /tmp/smmr2.yaml
  sed "/spec: /a \ \ members:" /tmp/smmr2.yaml > /tmp/smmr1.yaml
fi
cat /tmp/smmr1.yaml |grep $NSNAME > /dev/null
if [ $? != 0 ]; then
  echo "  - $NSNAME" >> /tmp/smmr1.yaml 
fi

oc apply -f /tmp/smmr1.yaml
### Adding NS to istio smmr - end

### Add anyuid scc to default sa in provided NS
oc adm policy add-scc-to-user anyuid -n $NSNAME -z default

### Create acr-pull-secret
oc get secret -n $NSNAME |grep acr-pull-secret > /dev/null
if [ $? = 0 ]; then
   echo "OK: secret acr-pull-secret already exists in namesapec $NSNAME"
else
   oc create secret docker-registry --docker-server=$acruserlower.azurecr.io --docker-username=$acruserupper --docker-password=$acrpas acr-pull-secret -n $NSNAME
fi

#Need to execute below patch command on your deployment after executing this script and before executing ns2.sh
#oc -n n patch deployment/<yourdeploymentname> -p '{"spec":{"template":{"metadata":{"annotations":{"sidecar.istio.io/inject": "true"}}}}}'

