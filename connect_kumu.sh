#!/bin/bash

rm `ls | grep -v *.md | grep -v connect_kumu.sh`

# if [ -s $AWS_PROFILE ]; then
#   aws sso logout
#   echo -e "Logging Out...!!"
# fi

unset AWS_PROFILE
AWS_CFG="${HOME}/.aws/config"

to_merge=false
logout=false

if [ -s $AWS_CFG ]; then
  # config file exists or not empry
  mv $AWS_CFG $AWS_CFG'.bak'
  to_merge=true
fi

main() {
  init

  if [ -f expect.sh ]; then
    startjob
  fi

  data

  if [[ $logout == false ]]; then
      config
  fi
}

init() {
  echo '#!/usr/bin/expect -f' > expect.sh
  echo spawn bash -c '"'aws configure sso \&\> getlogs.log'"' >> expect.sh
  echo expect '"'SSO start URL'"' >> expect.sh
  echo send '"'https://kumu.awsapps.com/start/#/'\\'r'"' >> expect.sh
  echo expect '"'SSO Region'"' >> expect.sh
  echo send '"'ap-southeast-1'\\'r'"' >> expect.sh
  echo expect '"'available to you.'"' >> expect.sh
  echo send '"''\\r''"' >> expect.sh
  echo expect '"'CLI default client Region'"' >> expect.sh
  echo send '"'ap-southeast-1'\\'r'"' >> expect.sh
  echo expect '"'CLI default output format'"' >> expect.sh
  echo send '"'json'\\'r'"' >> expect.sh
  echo expect '"'CLI profile name'"' >> expect.sh
  echo send '"''\\r''"' >> expect.sh
}

startjob() {
  chmod +x expect.sh
  clear
  echo "...Starting\n"
  bash -c './expect.sh &> /dev/null &'
}

data() {
  echo -e "\n\n\t[*] - Getting SSO Start URL..."
  while [[ true ]]; do
    grep -irnw getlogs.log -e "https://kumu.awsapps.com/start/#/" &> /dev/null
    if [[ $? -eq 0 ]]; then
      get_url=`grep -o "https://kumu.awsapps.com/start/#/" getlogs.log | uniq`
      echo -e "              \xE2\x9C\x94 $get_url"
      break
    fi
  done

  echo -e "\n\t[*] - Getting SSO Region..."
  while [[ true ]]; do
    grep -irnw getlogs.log -e "ap-southeast-1" &> /dev/null
    if [[ $? -eq 0 ]]; then
      get_sso_region=`grep -e "SSO Region" getlogs.log  | awk '{print$NF}' | grep -v "None"`
      echo -e "              \xE2\x9C\x94 $get_sso_region"
      break
    fi
  done

  echo -e "\n\t[*] - Getting AWS Accounts and Roles..."
  while [[ true ]]; do
    error=`grep -irnw getlogs.log -e "UnauthorizedException" &> /dev/null || echo $?`
    good=`grep -irnw getlogs.log -e "role" &> /dev/null || echo $?`
    if [[ $error -eq 0 ]]; then
      echo -e "              \xE2\x9D\x8C UnauthorizedException Found!\n"
      logout=true
      break
    fi

    if [[ $good -eq 0 ]]; then
      logout=false
      break
    fi
  done

  if [[ $logout == true ]]; then
    killall expect &> /dev/null
    echo -e "              Executing AWS SSO Logout...\n"
    aws sso logout
    echo -e "              Logged Out!! Please run the script again --> . ./connect_kumu.sh"
    exit &> /dev/null &
  else
    while [[ true ]]; do
      grep -irnw getlogs.log -e "role" &> /dev/null
      if [[ $? -eq 0 ]]; then
        ROLENAME=$(grep -e role getlogs.log | awk '{print$NF}' | head -n 1)
        total_acc=$(grep -e AWS getlogs.log | tr -dc '0-9')
        cat getlogs.log | grep -A$total_acc AWS | tail -n +2 | tr \> " " > accountlist.txt
        echo -e "             \xE2\x9C\x94 Role: $ROLENAME"
        echo -e "             \xE2\x9C\x94 Total Accounts: $total_acc"
        echo -e "             `cat accountlist.txt  | sed -e 's/^/\t/g'`"
        break
      fi
    done

    echo -e "\n\t[*] - Getting CLI default client Region..."
    while [[ true ]]; do
      grep -irnw getlogs.log -e "output" &> /dev/null
      if [[ $? -eq 0 ]]; then
        get_cli_region=`grep -e "client Region" getlogs.log | awk '{print$NF}' | grep -v "None"`      
        echo -e "             \xE2\x9C\x94 $get_cli_region"
        break
      fi
    done

    echo -e "\n\t[*] - Getting CLI default output format..."
    while [[ true ]]; do
      grep -irnw getlogs.log -e "profile" &> /dev/null
      if [[ $? -eq 0 ]]; then
        get_cli_format=`grep -e "format" getlogs.log | awk '{print$NF}' | grep -v "None"`
        echo -e "             \xE2\x9C\x94 $get_cli_format\n"
        break
      fi
    done
  fi
}

config() {
  declare -a ENV_NAME=(`cat accountlist.txt | awk '{print$1}' | tr -d ',' | cut -d @ -f1 | cut -d . -f2 | awk '{print toupper}' | sed -e 's/^ANDREW/PROD/g' -e 's/^DATAPLATFORM/DATA/g'`)
  declare -a ENV_EMAIL=(`cat accountlist.txt |  grep -oniE '[^[:blank:]]+@kumu.ph' | uniq | cut -d : -f2`)
  declare -a ENV_ACCID=(`cat accountlist.txt | grep -oE '[0-9]+'`)

  ## Create Custom AWS Config from Generated Profiles ##
  for e in ${ENV_ACCID[@]}; do
    PROFILES+=("$ROLENAME-$e")
    echo "[profile" $ROLENAME"-"$e"]" >> $AWS_CFG
    echo "sso_start_url = $get_url" >> $AWS_CFG
    echo "sso_region = $get_sso_region" >> $AWS_CFG
    echo "sso_account_id =" $e >> $AWS_CFG
    echo "sso_role_name =" $ROLENAME >> $AWS_CFG
    echo "region = $get_cli_region" >> $AWS_CFG
    echo "output = $get_cli_format" >> $AWS_CFG
  done

  clear; select_env

  rm `ls | grep -v *.md | grep -v connect_kumu.sh`

  if [[ $to_merge == true ]]; then
    backup
  fi
}

select_env() {
  echo -e "\n\t-+-+-+---  Choose Your AWS Account  ---+-+-+-\n"

  for (( i=1; i<=${#ENV_NAME[@]}; i++ )); do
    echo -e "\t|$i| >>" "\t${ENV_NAME[i]}" "\t(${ENV_ACCID[i]})" "-- ${ENV_EMAIL[i]}"
  done

  echo -e "\t[\xE2\x9D\x8C] ---- Enter any key to exit."
  echo -n "\n\tSelect your choice: "
  read CHOICE
  echo -e ""

  case "$CHOICE" in
    <1-7>) echo -e "\n\t${ENV_NAME[$CHOICE]} environment selected.";
        echo "\n\tConnecting using AWS profile ${PROFILES[$CHOICE]}\n";
        aws sso login --profile "${PROFILES[$CHOICE]}" > /dev/null;
        export AWS_PROFILE=${PROFILES[$CHOICE]};
        echo -e "";
        aws sts get-caller-identity;
        echo -e "";
        echo -e "\n\tBelow is your exported aws profile:\n";
        printenv | grep -i AWS_PROFILE | sed -e 's/^/\t/';;
    *) echo -e "\n\tYou entered $CHOICE which is invalid.";
        close;;
  esac
}

close() {
    echo -e "\n\tDo you want to try again?"
    echo -e "\tSelecting "NO" will close the program immediately."
    echo -n "\n\t[y/N]?"
    read yn
    echo -e ""

  case $yn in
    [Yy]*)  clear && select_env;;
    [Nn]*)  echo "\t\nTerminating...\n";
            terminate;;
        *)  echo -e "\n\tPlease answer Y or N only.";
            echo -e "";
            close;;
  esac
}

terminate() {
  if [[  $to_merge == true ]]; then
    mv $AWS_CFG'.bak' $AWS_CFG
  fi

  rm `ls | grep -v *.md | grep -v connect_kumu.sh`
  clear && exit &> /dev/null &
}

backup() {
  cat $AWS_CFG'.bak' | grep '^\[' > backup.txt
  cat $AWS_CFG | grep '^\[' > merge.txt

  declare -a BACKUP=(`cat backup.txt | tr ' ' '~' | sed -e 's/^/\"/' -e 's/$/\"/' | sort -n`)
  declare -a MERGE_NEW=(`cat merge.txt | tr ' ' '~' | sed -e 's/^/\"/' -e 's/$/\"/' | sort -n`)

  get_duplicates() {
    for b in ${BACKUP[@]}; do
      for n in ${MERGE_NEW[@]}; do
        if [[ "$b" == "$n" ]]; then
          echo $b >> duplicates.txt
        fi
      done
    done

    for d in `cat duplicates.txt`; do
      BACKUP=("${BACKUP[@]/"$d"}") 
    done
  }

  add_profiles() {
    for p in ${BACKUP[@]}; do
      echo $p | tr ' ' '~' | tr -d '"' >> add_profiles.txt
    done

    for a in `cat add_profiles.txt`; do
      echo -e "\n\t\xE2\x9C\x94 Added new profile "$a".\n"
      a=`echo $a | tr -d '[' | tr -d ']'`
      cat $AWS_CFG'.bak' | grep -A10 $a | tr '\n' ',' | cut -d '[' -f1,2 | tr ',' '\n' | sed -e '/^\s*$/d' >> $AWS_CFG
    done
  }

  get_duplicates

  if [[ ! -z ${BACKUP[@]} ]]; then
    add_profiles 2> /dev/null
  else
    echo -e "\n\t\xE2\x9D\x8C No new profiles merged.\n"
  fi

  rm `ls | grep -v *.md | grep -v connect_kumu.sh`
}

main "$@";
