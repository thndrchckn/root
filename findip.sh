awk 'c-->0;$0~s{if(b)for(c=b+1;c>1;c--)print r[(NR-c+1)%b];print;c=a}b{r[NR%b]=$0}' b=9 a=1 s="SUP*" /var/lib/dhcpd/dhcpd.leases
