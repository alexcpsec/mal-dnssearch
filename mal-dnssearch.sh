#!/bin/bash

# print stats: kill -USR2 $pid
trap "stats" SIGUSR2

# functions
usage()
{
cat <<EOF

Compare DNS logs against known mal-ware host list
      Options
	-a 	ARGUS file
        -b      BRO-IDS dns.log file
	-c      /etc/hosts file
        -d      Tcpdump pcap file
	-f      insert firewall rules e.g. iptables,pf,ipfw
	-h      help (this)
	-i	ISC's BIND query log file 
        -l      Log stdout & stderr to file
        -p      PassiveDNS log file
	-o      SonicWall NSA log file
	-s      Tshark pcap file
	-t      HttPry log file
        -w      Whitelist, accept file or argument
                e.g. -w "dont|match|these"

Usage: $0 [option] logfile [-w whitelist] [ -f fw ][-l output.log]
e.g. $0 -p /var/log/pdns.log -w "facebook|google" -f iptables -l output.log
EOF
}

stats()
{
echo " --> [-] stats: found: ${found}, current mal item: $tally of $total"
}

wlistchk()
{
if [ -z $WLISTDOM ]; then
echo "grep -v -i -E '(in-addr|\_)'"
elif [ -f $WLISTDOM ]; then
echo "grep -v -i -f $WLISTDOM"
else
echo "grep -v -i -E '(in-addr|$WLISTDOM)'"
fi
}

ipblock()
{
if [ "$FW" == "iptables" ]; then
iptables -A INPUT -s "$bad_host" -j DROP
iptables -A OUTPUT -s "$bad_host" -j DROP
iptables -A FORWARD -s "$bad_host" -j DROP
fi
if [ "$FW" == "pf" ]; then
echo -e "block in from yahoo.com to any\n \
block out from yahoo.com to any" | pfctl -a mal-dnssearch -f -
fi
if [ "$FW" == "ipfw" ]; then
ipfw add drop ip from "$bad_host" to any
ipfw add drop ip from any to "$bad_host"
fi
}

compare()
{
found=0
tally=0
echo -e "\n[*] |$PROG Results| - ${FILE}: comparing $logttl entries\n"
while read bad_host
do
let tally++

for host in $(eval "$1")
do
if [ "$bad_host" == "$host" ]; then
echo "[+] Found - host '"$host"' matches "

	if [ "$FWTRUE" == 1 ]; then
	ipblock
	fi

let found++
break
fi

done
done < <(cut -f1 < malhosts.txt | sed -e '/^#/d' -e '/^$/d')
echo -e "--\n[=] $found of $total entries matched from malhosts.txt\n"
}

# if less than 1 argument
if [ ! $# -gt 1 ]; then
usage
exit 1
fi

# option and argument handling
while getopts "ha:b:c:d:f:i:l:p:o:s:t:w:" OPTION
do
     case $OPTION in
	 a)
	     ARGUS=1
	     ARGUSFILE="$OPTARG"
	     ;;
         b)
             BRO=1
             BROFILE="$OPTARG"
             ;;
	 c) 
	     HOSTS=1
	     HOSTSFILE="$OPTARG"
	     ;; 
	 d) 
             TCPDUMP=1
             TCPDUMPFILE="$OPTARG"
             ;;
	 f)
	     FWTRUE=1
	     FW="$OPTARG"
	     ;;
         h)
             usage
             exit 1
             ;;
	 i) 
	     BIND=1
	     BINDFILE="$OPTARG"
	     ;; 
         l)
             LOG=1
             LOGFILE="$OPTARG"
             ;;
         p)
             PDNS=1
             PDNSFILE="$OPTARG"
             ;;
	 o) 
	     SWALL=1
	     SWALLFILE="$OPTARG"
	     ;;
	 s) 
    	     TSHARK=1
  	     TSHARKFILE="$OPTARG"
	     ;;
	 t)
	     HTTPRY=1
             HTTPRYFILE="$OPTARG"
	     ;;
         w)
             WLISTDOM="$OPTARG"
             ;;
         \?)
             exit 1
             ;;
     esac
done

echo -e "\nPID: $$"

# check for curl/wget and then d/l malhost list
if command -v curl >/dev/null 2>&1; then
curl -O http://secure.mayhemiclabs.com/malhosts/malhosts.txt &>/dev/null
elif command -v wget >/dev/null 2>&1; then
wget http://secure.mayhemiclabs.com/malhosts/malhosts.txt &>/dev/null
else
echo -e "\nERROR: Neither cURL or Wget are installed or are not in the \$PATH!\n"
exit 1
fi

# vars
total=$(sed -e '/^$/d' -e '/^#/d' < malhosts.txt | wc -l)
#logttl=$(wc -l $FILE | awk '{ print $1 }')

# logging
if [ "$LOG" == 1 ]; then
exec > >(tee "$LOGFILE") 2>&1
echo -e "\n --> Logging stdout & stderr to $LOGFILE"
fi

# meat
if [ "$BRO" == 1 ]; then
FILE=$BROFILE; PROG=BRO-IDS
compare "bro-cut query < \$BROFILE | $(eval wlistchk) | sort | uniq"
fi
if [ "$PDNS" == 1 ]; then
FILE=$PDNSFILE; PROG=PassiveDNS
compare "sed 's/||/:/g' < \$PDNSFILE | $(eval wlistchk) | cut -d \: -f5 | sed 's/\.$//' | sort | uniq"
fi
if [ "$HTTPRY" == 1 ]; then
FILE=$HTTPRYFILE; PROG=HttPry
compare "awk '{ print $7 }' < \$HTTPRYFILE | $(eval wlistchk) | sed -e '/^-$/d' -e '/^$/d' | sort | uniq"
fi
if [ "$TSHARK" == 1 ]; then
FILE=$TSHARKFILE; PROG=TShark
compare "tshark -nr \$TSHARKFILE -R udp.port==53 -e dns.qry.name -T fields 2>/dev/null \
| $(eval wlistchk) | sed -e '/#/d' | sort | uniq"
fi
if [ "$TCPDUMP" == 1 ]; then
FILE=$TCPDUMPFILE; PROG=TCPDump
compare "tcpdump -nnr \$TCPDUMPFILE udp port 53 2>/dev/null | grep -o 'A? .*\.' | $(eval wlistchk) \
 | sed -e 's/A? //' -e '/[#,\)\(]/d' -e '/^[a-zA-Z0-9].\{1,4\}$/d' -e 's/\.$//'| sort | uniq"
fi
if [ "$ARGUS" == 1 ]; then
FILE=$ARGUSFILE; PROG=ARGUS
compare "ra -nnr \$ARGUSFILE -s suser:512 - udp port 53 | $(eval wlistchk) | \
sed -e 's/s\[..\]\=.\{1,13\}//' -e 's/\.\{1,20\}$//' -e 's/^[0-9\.]*$//' -e '/^$/d' | sort | uniq"
fi
if [ "$BIND" == 1 ]; then
FILE=$BINDFILE; PROG=BIND
compare "awk '/query/ { print \$15 } /resolving/ { print \$13 }' \$BINDFILE | $(eval wlistchk) \ 
| grep -v resolving | sed -e 's/'\"'\"'//g' -e 's/\/.*\/.*://' -e '/[\(\)]/d' | sort | uniq"
fi 
if [ "$SWALL" == 1 ]; then
FILE=$SWALLFILE; PROG=SonicWALL
compare "grep -h -o 'dstname=.* a' \$SWALLFILE 2>/dev/null | $(eval wlistchk) \
| sed -e 's/dstname=//' -e 's/ a.*//' | sort | uniq"
fi 
if [ "$HOSTS" == 1 ]; then
FILE=$HOSTSFILE; PROG="Hosts File"
compare "sed -e '/^$/d' -e '/^#/d' < \$HOSTSFILE | $(eval wlistchk) | cut -f3 \
| awk 'BEGIN { RS=\" \"; OFS = \"\n\"; ORS = \"\n\" } { print }' | sed '/^$/d' | sort | uniq"
fi
