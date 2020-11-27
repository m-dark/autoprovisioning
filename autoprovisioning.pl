#!/usr/bin/perl -w
#Скрипт написал Крук Иван Александрович <kruk.ivan@itmh.ru>
use 5.010;
use strict;
use warnings;
use POSIX qw(strftime);
use locale;
use DBI;
use Time::Local;
use encoding 'utf-8';
#yum install perl-XML-SAX
#yum install perl-XML-Parser
use XML::Simple;
use Data::Dumper;
#use Date::Dumper qw(Dumper);
#fwconsole userman --syncall --force

my $dir = '/opt/asterisk/script_new';
my $dir_tftp = '/autoconfig_new';								#Директория для файлов конфигурации sip-телефонов .boot, .cfg и т.д.
my $dir_conf = "$dir/autoprovisioning";								#Директория для файлов конфигурации сервиса autoprovisioning.
my $dir_devices = "$dir/devices";								#Директория шаблонов конфигурации всех поддерживаемых моделей sip-телефонов.
my $dir_log = "$dir/log";									#Журналы
my $dir_history = "$dir/history";								#История изменений файлов конфигурации

my $host = '';				#"localhost"; # MySQL-сервер нашего хостинга
my $port = '';				#"3306"; # порт, на который открываем соединение
my $user = '';				#"freepbxuser"; # имя пользователя
my $pass = '';				#пароль /etc/freepbx.conf
my $db = '';				#"asterisk"; # имя базы данных.
my $vpn_root = '';			#0|1 (0 - no vpn, 1 - yes vpn)
my $tftp_ip = '';			#'tftp://X.X.X.X/';
my $internet_port_enable = "0";		#VLan Enable
my $internet_port_vid = "1";		#Number VLan
my $date_directory = strftime "%Y%m", localtime(time);						#Название каталога с историей изменений. (ГГГГММ)
my $date_time_file = strftime "%Y-%m-%d_%H%M%S", localtime(time);				#Переменная хранит в себе дату и время запуска скрипта, для понимания, когда вносились изменения.
my $tmp_dir = '/tmp';
my $size_displayname = "15";									#Переменная, которая говорит нам, какой максимальной длины должна быть в тел. справочнике учетка. (displayname)
my $date_time_file_now = '';
my $difference_in_time = '';
my $reload_yes = 0;
#my $script_dir = Заменил на $dir;
#my $history_dir = "заменил на dir_history";

my %hash_number_line = ();									#Хэш содержит mac-адреса sip-телефонов с номерами телефонов и номерами аккаунтов (линий), к которым привязаны эти номера.
my %hash_named = ();										#Номера групп из файла conf_number_line.conf, имеют приоритет!
my %hash_local_cfg_mac = ();									#{MAC-адрес}{handset.1.name} = {Приёмная}
my %hash_local_cfg_print = ();									#{MAC-адрес}{Статическая строка файла конфигурации например handset.1.name = Приёмная}=1 , для файла "mac"local.cfg
my %hash_cfg_mac = ();										#{MAC-адрес}{network.vlan.internet_port_enable} = {0}
my %hash_named_db = ();										#номера групп из BD FreePBX
my %hash_namedgroup = ();									#номера групп из файла namedgroup.conf, содержит шаблоны по автозаполнению групп!
my %hash_vpn_user_enable = ();									#мак адрес у которого вклюючен VPN
my %hash_sipid_displayname = ();								#номер телефона и ФИО сотрудника Иванов И.И.
my %hash_brand_model_conf = ();									#Содержит все шаблоны файлов конфигурации для sip-телефонов, которые поддерживает данная версия скрипта. !!! Структура хэша немного изменилась, появился еще brand hash_model_conf
#####*Добавить бренд?
my %hash_mac_model = ();									#Хэш mac-адресов с версией модели SIP-телефона. (Для проверки корректно внесенной информации о модели sip-телефона на разных учетках AD).
my %hash_mac_phone_pass = ();									#Хэш содержит mac-адреса sip-телефонов с номерами телефонов и паролями от sip-учеток этих номеров.
my %hash_displayname = ();									#Хэш который содержит в себе displayname из файла freepbx.pass, которые необходимо заменить для справочника.
my %hash_dir_files = ();									#Хэш содержит список файлов конфигураций для всех sip-телефонов из каталога TFTP-server (для удаления sip-учетки на sip-телефонах, которые удалили из AD)
my %hash_template_yealink = ();									#Хэш содержит конфигурацию шаблона из файла XXXPPP.cfg {"mac yealinka"}{"номер строки"}{"Знпачение до равно"} = "Значение после ="

open (my $file_conf_number_line, '<:encoding(UTF-8)', "$dir_conf/conf_number_line.conf") || die "Error opening file: conf_number_line.conf $!";
	while (defined(my $line_number_line = <$file_conf_number_line>)){
		chomp ($line_number_line);
		my @array_number_line = split (/\t/,$line_number_line,-1);
		$hash_number_line{$array_number_line[0]}{$array_number_line[1]} = $array_number_line[2];
		if (defined $array_number_line[3]){
			$hash_named{$array_number_line[1]}{namedcallgroup} = $array_number_line[3];
		}else{
			$hash_named{$array_number_line[1]}{namedcallgroup} = '';
		}
		if (defined $array_number_line[4]){
			$hash_named{$array_number_line[1]}{namedpickupgroup} = $array_number_line[4];
		}else{
			$hash_named{$array_number_line[1]}{namedpickupgroup} = '';
		}
	}
close ($file_conf_number_line);

open (my $freepbx_pass, '<:encoding(UTF-8)', "$dir_conf/freepbx.pass") || die "Error opening file: freepbx.pass $!";
        while (defined(my $line_freepbx_pass = <$freepbx_pass>)){
                if ($line_freepbx_pass =~ /^\#|^\;/){
                        next;
                }
                chomp ($line_freepbx_pass);
                my @array_freepbx_pass = split (/ = /,$line_freepbx_pass,2);
                given($array_freepbx_pass[0]){
                        when('host'){
                                $host = $array_freepbx_pass[1];
                        }when('port'){
                                $port = $array_freepbx_pass[1];
                        }when('user'){
                                $user = $array_freepbx_pass[1];
                        }when('pass'){
                                $pass = $array_freepbx_pass[1];
                        }when('db'){
                                $db = $array_freepbx_pass[1];
                        }when('vpn_root'){
                                $vpn_root = $array_freepbx_pass[1];
                        }when('tftp_ip'){
                                $tftp_ip = $array_freepbx_pass[1];
                        }when('local_cfg'){
                                my @array_local_cfg = split(/\;/,$array_freepbx_pass[1],-1);
                                foreach my $numper_local_cfg (@array_local_cfg){
                                        my @array_number_local_cfg = split (/:/,$numper_local_cfg,2);
                                        $array_number_local_cfg[0] =~ s/ //;
                                        my @array_number_local_cfg_mac = split(/ = /,$array_number_local_cfg[1],2);
                                        if ($array_number_local_cfg[0] =~ /-/){
                                                my @array_number_local_cfg_start_end = split(/-/,$array_number_local_cfg[0],2);
                                                if($array_number_local_cfg_start_end[0] < $array_number_local_cfg_start_end[1]){
                                                        while($array_number_local_cfg_start_end[0] != ($array_number_local_cfg_start_end[1]+1)){
                                                                foreach my $key_mac (sort keys %hash_number_line){
                                                                        if (exists($hash_number_line{$key_mac}{$array_number_local_cfg_start_end[0]})){
##                                                                              print("$array_number_local_cfg_start_end[0]\t$key_mac\t$array_number_local_cfg[1]\n");
                                                                                if (exists($hash_local_cfg_mac{$key_mac}{$array_number_local_cfg_mac[0]})){
##                                                                                      print("$array_number_local_cfg[1]\n");
                                                                                }else{
                                                                                        $hash_local_cfg_print{$key_mac}{$array_number_local_cfg[1]} = 1;
                                                                                }
                                                                                $hash_local_cfg_mac{$key_mac}{$array_number_local_cfg_mac[0]} = $array_number_local_cfg_mac[1];
                                                                                next;
                                                                        }
                                                                }
                                                                $array_number_local_cfg_start_end[0]++;
                                                        }
                                                }
                                        }else{
                                                foreach my $key_mac (sort keys %hash_number_line){
                                                        if (exists($hash_number_line{$key_mac}{$array_number_local_cfg[0]})){
##                                                              print("$array_number_local_cfg[0]\t$key_mac\t$array_number_local_cfg[1]\n");
                                                                if (exists($hash_local_cfg_mac{$key_mac}{$array_number_local_cfg_mac[0]})){
                                                                }else{
                                                                        $hash_local_cfg_print{$key_mac}{$array_number_local_cfg[1]} = 1;
                                                                }
                                                                $hash_local_cfg_mac{$key_mac}{$array_number_local_cfg_mac[0]} = $array_number_local_cfg_mac[1];
                                                                last;
                                                        }
                                                }
                                        }
                                }
                        }when('mac_cfg'){
                                my @array_cfg = split(/\;/,$array_freepbx_pass[1],-1);
                                foreach my $numper_cfg (@array_cfg){
                                        my @array_number_cfg = split (/:/,$numper_cfg,2);
                                        $array_number_cfg[0] =~ s/ //;
                                        my @array_number_cfg_mac = split(/ = /,$array_number_cfg[1],2);
                                        if ($array_number_cfg[0] =~ /-/){
                                                my @array_number_cfg_start_end = split(/-/,$array_number_cfg[0],2);
                                                if($array_number_cfg_start_end[0] < $array_number_cfg_start_end[1]){
                                                        while($array_number_cfg_start_end[0] != ($array_number_cfg_start_end[1]+1)){
                                                                foreach my $key_mac (sort keys %hash_number_line){
                                                                        if (exists($hash_number_line{$key_mac}{$array_number_cfg_start_end[0]})){
                                                                                $hash_cfg_mac{$key_mac}{$array_number_cfg_mac[0]} = $array_number_cfg_mac[1];
                                                                                next;
                                                                        }
                                                                }
                                                                $array_number_cfg_start_end[0]++;
                                                        }
                                                }
                                        }else{
                                                foreach my $key_mac (sort keys %hash_number_line){
                                                        if (exists($hash_number_line{$key_mac}{$array_number_cfg[0]})){
                                                                $hash_cfg_mac{$key_mac}{$array_number_cfg_mac[0]} = $array_number_cfg_mac[1];
                                                                last;
                                                        }
                                                }
                                        }
                                }
                        }when('network.vlan.internet_port_enable'){
                                $internet_port_enable = $array_freepbx_pass[1];
                        }when('network.vlan.internet_port_vid'){
                                $internet_port_vid = $array_freepbx_pass[1];
                        }when('size_displayname'){
                    		$size_displayname = $array_freepbx_pass[1];
                    	}when('displayname'){
                    		my @array_displayname = split (/ - /,$array_freepbx_pass[1],2);
                    		$hash_displayname{$array_displayname[0]} = $array_displayname[1];
                        }default{
                                next;
                        }
                }
        }
close($freepbx_pass);

open (my $file_brand_model, '<:encoding(UTF-8)', "$dir_conf/brand_model.cfg") || die "Error opening file: brand_model.cfg $!";
	my $brand = '';
        while (defined(my $line_file_brand_model = <$file_brand_model>)){
                if ($line_file_brand_model =~ /^(\#|\;|$)/){
                        next;
                }
                chomp ($line_file_brand_model);
                if($line_file_brand_model =~ /^\[/){
			$line_file_brand_model =~ s/\[//;
			$line_file_brand_model =~ s/\]//;
			$brand = $line_file_brand_model;
                }else{
			$hash_brand_model_conf{$brand}{$line_file_brand_model}{'name_cfg'} = "${line_file_brand_model}.cfg";
			open (my $name_cfg, '<:encoding(UTF-8)', "$dir_devices/$brand/$line_file_brand_model/${line_file_brand_model}.cfg") || die "Error opening file: $dir_devices/$brand/$line_file_brand_model/${line_file_brand_model}.cfg $!";
				while (defined(my $line_name_cfg = <$name_cfg>)){
            				if ($line_name_cfg =~ /^\#|^\;/){
                    				next;
			                }
			                chomp ($line_name_cfg);
			                my @array_name_cfg = split (/ = /,$line_name_cfg,-1);
			                given($array_name_cfg[0]){
		                    		when('mac_boot'){
		                            		$hash_brand_model_conf{$brand}{$line_file_brand_model}{'mac_boot'} = $array_name_cfg[1];
                		    		}default{
                		    			next;
                		    		}
                		    	}
                		}
                	close($name_cfg);
                }
	}
close ($file_brand_model);

#Считываем названия файлов конфигурации из каталога TFTP-server
#Yealink
chdir "$dir_tftp" or die "No open $dir_tftp $!";
my @dir_files = glob "[0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z][0-9a-z].cfg";
foreach my $file_old (@dir_files){
	$file_old =~ s/.cfg//;
	$hash_dir_files{'yealink'}{$file_old} = 1;
}

#Cisco
@dir_files = glob "SEP[0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z][0-9A-Z].cnf.xml";
foreach my $file_old (@dir_files){
	$file_old =~ s/.cnf.xml//;
	$file_old =~ s/SEP//;
#к верхнему uc()
#	$file_old = lc($file_old);
	$hash_dir_files{'cisco'}{$file_old} = 1;
}

#Создаем каталог в history, если наступило новео число.
opendir (CD, "$dir_history") || mkdir "$dir_history", 0744;
closedir (CD);
opendir (HIS, "$dir_history/$date_directory") || ((mkdir "$dir_history/$date_directory/", 0744) and (`chown asterisk:asterisk $dir_history/$date_directory`));
closedir (HIS);

#Создаем файл с параметрами для номеров телефонов.!!!Скорее всего в него необходимо еще добавить бренд.
my $yes_ad_sip_phone = `ls -la $dir_conf| grep ad_sip-phone.txt\$`;
if ($yes_ad_sip_phone eq ''){
	open (my $file, '>:encoding(UTF-8)', "$dir_conf/ad_sip-phone.txt") || die "Error opening file: ad_sip-phone.txt $!";
	close ($file);
}

#Считываем номера, у которых в атрибуте с моделью sip-телефона пусто. (Это нам говорит о том, что данный номер телефона необходимо скрыть в тел. справочнике).
my $dbasterisk = DBI->connect("DBI:mysql:$db:$host:$port",$user,$pass,{ mysql_enable_utf8 => 1 });
my $sth_ad = $dbasterisk->prepare("SELECT sip.id,sip.data,userman_users.fax,userman_users.home FROM sip,userman_users where sip.id = userman_users.work AND sip.keyword = 'secret' AND userman_users.home = '';");
$sth_ad->execute; # исполняем запрос
while (my $ref = $sth_ad->fetchrow_arrayref) {
	my $ok = 0;
	open (my $file_ad_sip_phone_txt, '<:encoding(UTF-8)', "$dir_conf/ad_sip-phone.txt") || die "Error opening file: ad_sip-phone.txt $!";
		while (defined(my $line_file_ad_sip_phone_txt = <$file_ad_sip_phone_txt>)){
			chomp ($line_file_ad_sip_phone_txt);
			my @array_line_file_ad_sip_phone_txt = split (/\t/,$line_file_ad_sip_phone_txt,-1);
			if ("$$ref[0]" == $array_line_file_ad_sip_phone_txt[0]){
				print "Скрытый номер: $$ref[0]\n";
				$ok = 1;
				$hash_mac_model{$array_line_file_ad_sip_phone_txt[2]} = $array_line_file_ad_sip_phone_txt[3];
				$hash_mac_phone_pass{$array_line_file_ad_sip_phone_txt[2]}{$array_line_file_ad_sip_phone_txt[0]} = $array_line_file_ad_sip_phone_txt[1];#$hash_sip_phone
				$hash_named_db{$array_line_file_ad_sip_phone_txt[0]}{namedcallgroup} = $array_line_file_ad_sip_phone_txt[4];
				$hash_named_db{$array_line_file_ad_sip_phone_txt[0]}{namedpickupgroup} = $array_line_file_ad_sip_phone_txt[5];
				last;
			}
		}
		if ($ok == 0){
			print "ERROR 6, У номера $$ref[0] необходимо в AD заполнить все атрибуты.\n";
		}
	close ($file_ad_sip_phone_txt);
}
my $rc = $sth_ad->finish;

#Считываем информацию из файла о том, какие номера к какой группе относились. (До внесения изменений).
open (my $file_group, '<:encoding(UTF-8)', "$dir_conf/namedgroup.conf") || die "Error opening file: namedgroup.conf $!";
	while (defined(my $line_namedgroup = <$file_group>)){
		if ($line_namedgroup =~ /^\d/){
			chomp ($line_namedgroup);
			my @array_namedgroup = split (/\t/,$line_namedgroup,-1);
			if ($array_namedgroup[0] =~ /^(\d+\-\d+)$/){
				print "1\n";
				my @array_namedgroup_number = split (/\-/,$array_namedgroup[0],-1);
				if ($array_namedgroup_number[0] < $array_namedgroup_number[1]){
					while ($array_namedgroup_number[0] <= $array_namedgroup_number[1]){
						$hash_namedgroup{$array_namedgroup_number[0]}{namedcallgroup} = $array_namedgroup[1];
						$hash_namedgroup{$array_namedgroup_number[0]}{namedpickupgroup} = $array_namedgroup[2];
						$hash_namedgroup{$array_namedgroup_number[0]}{counter} += 1;
						$array_namedgroup_number[0]++;
						print "$array_namedgroup_number[0]\n";
					}
				}else{
					print "ERROR_4, $array_namedgroup_number[0] > $array_namedgroup_number[1]\n";
				}
			}elsif ($array_namedgroup[0] =~ /^(\dX)/){
				my $start_namedgroup_number = $array_namedgroup[0];
				my $end_namedgroup_number = $array_namedgroup[0];
				$start_namedgroup_number =~ s/X/0/g;
				$end_namedgroup_number =~ s/X/9/g;
				while ($start_namedgroup_number <= $end_namedgroup_number){
					$hash_namedgroup{$start_namedgroup_number}{namedcallgroup} = $array_namedgroup[1];
					$hash_namedgroup{$start_namedgroup_number}{namedpickupgroup} = $array_namedgroup[2];
					$hash_namedgroup{$start_namedgroup_number}{counter} += 1;
					$start_namedgroup_number++;
				}
			}elsif ($array_namedgroup[0] =~ /^(\d+)$/){
				$hash_namedgroup{$array_namedgroup[0]}{namedcallgroup} = $array_namedgroup[1];
				$hash_namedgroup{$array_namedgroup[0]}{namedpickupgroup} = $array_namedgroup[2];
				$hash_namedgroup{$array_namedgroup[0]}{counter} += 1;
			}else{
				print "ERROR_5, $array_namedgroup[0]\n";
			}
		}
	}
close ($file_group);

#проверка на дубли номеров
foreach my $key_namedgroup (sort keys %hash_namedgroup){
	if ($hash_namedgroup{$key_namedgroup}{counter} > 1){
		print "ERROR_6, в файле namedgroup.conf номер $key_namedgroup повторяется $hash_namedgroup{$key_namedgroup}{counter} раз(а)\n";
		exit;
	}
}

#Выгружаем из базы FreePBX список номеров и displayname к ним для телефонного справочника.
my $sth_sipid = $dbasterisk->prepare("SELECT sip.id,displayname FROM sip,userman_users where sip.id = userman_users.work AND sip.keyword = 'secret';");
$sth_sipid->execute; # исполняем запрос
while (my $ref = $sth_sipid->fetchrow_arrayref) {
	if (exists($hash_displayname{$$ref[1]})){
		$hash_sipid_displayname{$$ref[0]} = $hash_displayname{$$ref[1]};
		next;
	}
	if ($$ref[1] =~ /^[А-Я][а-я]+\s[А-Я][а-я]+\s[А-Я][а-я]+$/){
		my @array_fio = split (/ /,$$ref[1],-1);
		my $name = substr($array_fio[1],0,1);
		my $otc = substr($array_fio[2],0,1);
#		print "$array_fio[0] $name\.$otc\.\n";
		$hash_sipid_displayname{$$ref[0]} = "$array_fio[0] $name\.$otc\.";
	}elsif ($$ref[1] =~ /^[А-Я][а-я]+\s[А-Я][а-я]+\s[А-Я][а-я]+\s\d+$/){
		my @array_fio = split (/ /,$$ref[1],-1);
		my $name = substr($array_fio[1],0,1);
		my $otc = substr($array_fio[2],0,1);
#		print "$array_fio[0] $name\.$otc\.$array_fio[3]\n";
		$hash_sipid_displayname{$$ref[0]} = "$array_fio[0] $name\.$otc\.$array_fio[3]";
	}elsif($$ref[1] =~ /^.{0,$size_displayname}$/){
		$hash_sipid_displayname{$$ref[0]} = $$ref[1];
		print "$$ref[0]\t$$ref[1]\n";
	}else{
		my $fio = substr($$ref[1],0,$size_displayname);
		$hash_sipid_displayname{$$ref[0]} = $fio;
		print "$$ref[0]\t$fio\n";
	}
}
$rc = $sth_sipid->finish;

#print "Content-type: text/html\n\n";
#my $dbasterisk = DBI->connect("DBI:mysql:$db:$host:$port",$user,$pass);
#my $sth = $dbasterisk->prepare("SELECT sip.id,sip.data,userman_users.fax,userman_users.home FROM sip,userman_users where sip.id = userman_users.work AND sip.keyword = 'secret';");
#Выгружаем данные из базы, для формирования нового файла /tmp/"date"_ad_sip-phone.txt
#  id        | secret                           | fax          | home  | namedcallgroup | namedpickupgroup |
#+-----------+----------------------------------+--------------+-------+----------------+------------------+
#| 100       | 023b472dbd226726cfe4adf7b6acd3b4 | 805ec002fa0d | cp920 |                |                  |
######**Здесь скорее всего надо встроить проверку бренда!
my $sth = $dbasterisk->prepare("select a.id, max(secret) secret, fax, home, max(namedcallgroup) namedcallgroup, max(namedpickupgroup) namedpickupgroup from (select distinct id, case when keyword = 'secret' then data end secret, case when keyword = 'namedcallgroup' then data end namedcallgroup, case when keyword = 'namedpickupgroup' then data end namedpickupgroup from sip where keyword in ('secret','namedcallgroup','namedpickupgroup')) a left join userman_users u on u.work = a.id group by a.id, fax, home;");
$sth->execute; # исполняем запрос

#open ($file, '>>:encoding(UTF-8)', "$dir_conf/ad_sip-phone.txt") || die "Error opening file: ad_sip-phone.txt $!";
open (my $file, '>>:encoding(UTF-8)', "$tmp_dir/${date_time_file}_ad_sip-phone.txt") || die "Error opening file: ${date_time_file}_ad_sip-phone.txt $!";
	while (my $ref = $sth->fetchrow_arrayref) {
		if((defined ($$ref[3])) && ($$ref[3] =~ /\./)){
			my @array_ref_3 = split (/\./,$$ref[3],-1);
			$$ref[3] = $array_ref_3[0];
			shift(@array_ref_3);
			foreach my $vpn_or_vlan (@array_ref_3){
				if (($vpn_or_vlan eq 'vpn') || ($vpn_or_vlan eq 'VPN')){
					$hash_vpn_user_enable{"\L$$ref[2]"} = 1;
				}elsif (($vpn_or_vlan =~ /^vlan=/) || ($vpn_or_vlan =~ /^Vlan=/) || ($vpn_or_vlan =~ /^VLAN=/)){
					my @vlan_number = split (/=/,$vpn_or_vlan,2);
					if ($vlan_number[1] == 0){
						$hash_cfg_mac{"\L$$ref[2]"}{'network.vlan.internet_port_enable'} = 0;
						$hash_cfg_mac{"\L$$ref[2]"}{'network.vlan.internet_port_vid'} = 1;

					}else{
						$hash_cfg_mac{"\L$$ref[2]"}{'network.vlan.internet_port_enable'} = 1;
						$hash_cfg_mac{"\L$$ref[2]"}{'network.vlan.internet_port_vid'} = $vlan_number[1];
					}
				}else{
					print "Error 111: VPN or VLAN\n";
				}
			}
		}
#		print "$$ref[0]\t$$ref[1]\t$$ref[2]\t$$ref[3]\t$$ref[4]\n";
		if (defined ($$ref[2] && $$ref[3])){
			if($$ref[2] =~ /[а-яА-Я]/){
				print "Error_7, В mac-адресе $$ref[2] присутствует русская буква!\n";
			}
			if (exists($hash_mac_model{"\L$$ref[2]"})){
				if (($hash_mac_model{"\L$$ref[2]"} ne "$$ref[3]") && ("$$ref[3]" ne '')){
					print "ERROR_2: За mac-адресом \L$$ref[2] уже прописана модель $hash_mac_model{\"\L$$ref[2]\"}, а вы пытаетесь прописать за ним новую модель $$ref[3]\n";
					next;
				}else{
#					print "Тест на скрытый номер: $$ref[2]\t $$ref[3]\n";
				}
			}else{
				$hash_mac_model{"\L$$ref[2]"} = lc("$$ref[3]");
			}
			$hash_mac_phone_pass{"\L$$ref[2]"}{"$$ref[0]"} = "$$ref[1]";
			$hash_named_db{"$$ref[0]"}{namedcallgroup} = "$$ref[4]";
			$hash_named_db{"$$ref[0]"}{namedpickupgroup} = "$$ref[5]";
#			print $file "$$ref[0]\t$$ref[1]\t\L$$ref[2]\t$$ref[3]\t$$ref[4]\t$$ref[5]\n";
		}else{
			print "ERROR_3: В FreePBX  номер $$ref[0] создан, а в AD его не стало. (можно удалить из exten, если этот номер там не нужен)\n";
			next;
		}
	}
	foreach my $key_sip_phone_mac (sort keys %hash_mac_phone_pass){
		foreach my $key_sip_phone_number (sort keys %{$hash_mac_phone_pass{$key_sip_phone_mac}}){
			print $file "$key_sip_phone_number\t$hash_mac_phone_pass{$key_sip_phone_mac}{$key_sip_phone_number}\t$key_sip_phone_mac\t$hash_mac_model{$key_sip_phone_mac}\t$hash_named_db{$key_sip_phone_number}{namedcallgroup}\t$hash_named_db{$key_sip_phone_number}{namedpickupgroup}\n"; # печатаем результат
		}
	}
close ($file);

$rc = $sth->finish;
$rc = $dbasterisk->disconnect;  # закрываем соединение

#Удаляем sip-учетки в тех файлах конфигураций, которые были удалены из AD.
foreach my $key_brand (sort keys %hash_dir_files){
	foreach my $key_dir_files (sort keys %{$hash_dir_files{$key_brand}}){
		if (exists($hash_mac_model{$key_dir_files})){
			
		}else{
			if($key_brand eq 'yealink'){
				$key_dir_files = "${key_dir_files}.cfg"
			}elsif($key_brand eq 'cisco'){
				$key_dir_files = "SEP${key_dir_files}.cnf.xml"
			}
			&number_zero($key_brand, $key_dir_files);
			&diff_file("$dir_tftp", "$tmp_dir", "$key_dir_files");
		}
	}
}

#Удаляем номер телефона и номер Аккаунта, к которому привязан данный номер телефона, если номер был удален в AD.
foreach my $key_mac_address (sort keys %hash_number_line){
	foreach my $key_number (keys %{$hash_number_line{$key_mac_address}}){
		if (exists($hash_mac_phone_pass{$key_mac_address}{$key_number})){
		}else{
			delete $hash_number_line{$key_mac_address}{$key_number};
		}
	}
}

#Прописываем новые номера и номер аккаунта для номера.
foreach my $key_mac_address (sort keys %hash_mac_phone_pass){
	foreach my $key_number (keys %{$hash_mac_phone_pass{$key_mac_address}}){
		if (exists($hash_number_line{$key_mac_address}{$key_number})){
#		&add_line ("$key_mac_address","$key_number");
		}else{
			&add_line ("$key_mac_address","$key_number");
		}
	}
}

#Создаем файл конфигурации для sip-телефона.
my $brand_yealink = 'yealink';
my $brand_cisco = 'cisco';

open (my $file_1, '>:encoding(UTF-8)', "$tmp_dir/${date_time_file}_conf_number_line.conf") || die "Error opening file: ${date_time_file}_conf_number_line.conf $!";
foreach my $key_number_line_mac (sort keys %hash_number_line){
#Формируем новый файл conf_number_line.conf
	foreach my $key_number_line_number(sort { $hash_number_line{$key_number_line_mac}{$a} <=> $hash_number_line{$key_number_line_mac}{$b} } keys %{$hash_number_line{$key_number_line_mac}}){
		my $namedcallgroup = '';
		my $namedpickupgroup = '';
		if(exists ($hash_namedgroup{$key_number_line_number})){
			$namedcallgroup = $hash_namedgroup{$key_number_line_number}{namedcallgroup};
			$namedpickupgroup = $hash_namedgroup{$key_number_line_number}{namedpickupgroup};
		}
		if ((exists ($hash_named{$key_number_line_number})) && ($hash_named{$key_number_line_number}{namedcallgroup} ne '')){
			$namedcallgroup = $hash_named{$key_number_line_number}{namedcallgroup};
		}
		if ((exists ($hash_named{$key_number_line_number})) && ($hash_named{$key_number_line_number}{namedpickupgroup} ne '')){
			$namedpickupgroup = $hash_named{$key_number_line_number}{namedpickupgroup};
		}
		if ($namedcallgroup ne $hash_named_db{$key_number_line_number}{namedcallgroup}){
#			print "!!!!!!!!!!!!!$namedcallgroup $hash_named_db{$key_number_line_number}{namedcallgroup}\n";
			&update_namedcallgroup ($key_number_line_number, $namedcallgroup, $hash_named_db{$key_number_line_number}{namedcallgroup});
		}
		if ($namedpickupgroup ne $hash_named_db{$key_number_line_number}{namedpickupgroup}){
#			print "!!!!!!!!!!!!!$namedpickupgroup $hash_named_db{$key_number_line_number}{namedpickupgroup}\n";
			&update_namedpickupgroup ($key_number_line_number, $namedpickupgroup, $hash_named_db{$key_number_line_number}{namedpickupgroup});
		}
		print $file_1 "$key_number_line_mac\t$key_number_line_number\t$hash_number_line{$key_number_line_mac}{$key_number_line_number}\t$namedcallgroup\t$namedpickupgroup\n";
	}
#Формируем файлы конфигурации для Yealink
	if(exists($hash_brand_model_conf{"$brand_yealink"}{$hash_mac_model{$key_number_line_mac}})){
		if ($vpn_root == 1){
			opendir (VPN_CFG, "$dir_tftp/$key_number_line_mac/") || ((mkdir "$dir_tftp/$key_number_line_mac/", 0744) && (`cp -f $dir_tftp/template_vpn_conf/client.tar $dir_tftp/$key_number_line_mac/ && chown -R tftpd:tftpd $dir_tftp/$key_number_line_mac`));
			closedir (VPN_CFG);
		}
#Создаем файл конфигурации для Yealink "mac".boot
		&conf_boot('yealink', "$key_number_line_mac", "$hash_mac_model{$key_number_line_mac}");
#Создаем файл конфигурации для Yealink "mac".cfg
		open (my $file_cfg, '>:encoding(utf-8)', "$tmp_dir/${date_time_file}_${key_number_line_mac}.cfg") || die "Error opening file: ${date_time_file}_${key_number_line_mac}.cfg $!";
			print $file_cfg "#!version:1.0.0.1\n";
			my $number_line = 0;
			foreach my $key_number_line_number(sort { $hash_number_line{$key_number_line_mac}{$a} <=> $hash_number_line{$key_number_line_mac}{$b} } keys %{$hash_number_line{$key_number_line_mac}}){
				open (my $file_xxx_ppp, '<:encoding(UTF-8)', "$dir_conf/XXXPPP.cfg") || die "Error opening file: XXXPPP.cfg $!";
					while (defined(my $line_cfg = <$file_xxx_ppp>)){
						if ($line_cfg =~ /^(\#|\;)/){
							next;
						}
						chomp ($line_cfg);
						if ($line_cfg =~ /^(account.0.label = |account.0.display_name = |account.0.auth_name = |account.0.user_name = )$/){
							$line_cfg =~ s/account.0//;
							my @mas_line_cfg_template = split(/ = /,$line_cfg,-1);
							$hash_template_yealink{$key_number_line_mac}{$number_line}{"account."."$hash_number_line{$key_number_line_mac}{$key_number_line_number}"."$mas_line_cfg_template[0]"} = $key_number_line_number;
						}elsif ($line_cfg =~ /^account.0.password = $/){
							$line_cfg =~ s/account.0//;
							my @mas_line_cfg_template = split(/ = /,$line_cfg,-1);
							$hash_template_yealink{$key_number_line_mac}{$number_line}{"account."."$hash_number_line{$key_number_line_mac}{$key_number_line_number}"."$mas_line_cfg_template[0]"} = $hash_mac_phone_pass{$key_number_line_mac}{$key_number_line_number};
						}elsif ($line_cfg =~ /^account.0./){
							$line_cfg =~ s/account.0//;
							my @mas_line_cfg_template = split(/ = /,$line_cfg,-1);
							$hash_template_yealink{$key_number_line_mac}{$number_line}{"account."."$hash_number_line{$key_number_line_mac}{$key_number_line_number}"."$mas_line_cfg_template[0]"} = $mas_line_cfg_template[1];
						}elsif($line_cfg =~ /^(|$)/){
							$hash_template_yealink{$key_number_line_mac}{$number_line}{'probel'} = 1;
						}else{
							my @mas_line_cfg_template = split(/ = /,$line_cfg,-1);
							$hash_template_yealink{$key_number_line_mac}{$number_line}{$mas_line_cfg_template[0]} = $mas_line_cfg_template[1];
						}
						$number_line++;
					}
				close ($file_xxx_ppp);
			}
			if (exists($hash_vpn_user_enable{$key_number_line_mac})){
				$hash_template_yealink{$key_number_line_mac}{$number_line}{'network.vpn_enable'} = 1;
				$number_line++;
				$hash_template_yealink{$key_number_line_mac}{$number_line}{'openvpn.url'} = "${tftp_ip}${key_number_line_mac}/client.tar";
			}else{
				$hash_template_yealink{$key_number_line_mac}{$number_line}{'network.vpn_enable'} = 0;
			}
			$number_line++;
			if (exists($hash_cfg_mac{$key_number_line_mac}{'network.vlan.internet_port_enable'})){
				$hash_template_yealink{$key_number_line_mac}{$number_line}{'network.vlan.internet_port_enable'} = $hash_cfg_mac{$key_number_line_mac}{'network.vlan.internet_port_enable'};
			}else{
				$hash_template_yealink{$key_number_line_mac}{$number_line}{'network.vlan.internet_port_enable'} = $internet_port_enable;
			}
			$number_line++;
			if (exists($hash_cfg_mac{$key_number_line_mac}{'network.vlan.internet_port_vid'})){
				if ($hash_cfg_mac{$key_number_line_mac}{'network.vlan.internet_port_vid'} == 0){
				}else{
					$hash_template_yealink{$key_number_line_mac}{$number_line}{'network.vlan.internet_port_vid'} = $hash_cfg_mac{$key_number_line_mac}{'network.vlan.internet_port_vid'};
				}
			}else{
				$hash_template_yealink{$key_number_line_mac}{$number_line}{'network.vlan.internet_port_vid'} = $internet_port_vid;
			}
			$number_line++;
			foreach my $key_numline (sort { $a <=> $b}  keys %{$hash_template_yealink{$key_number_line_mac}}){
				foreach my $key_line (sort keys %{$hash_template_yealink{$key_number_line_mac}{$key_numline}}){
					if (exists($hash_cfg_mac{$hash_template_yealink{$key_number_line_mac}{$key_numline}})){
						print $file_cfg "$key_line".' = '."$hash_cfg_mac{$key_number_line_mac}{$key_line}\n";
					}else{
						if($key_line eq 'probel'){
							print $file_cfg "\n";
						}else{
							print $file_cfg "$key_line".' = '."$hash_template_yealink{$key_number_line_mac}{$key_numline}{$key_line}\n";
						}
					}
				}
			}
		close ($file_cfg);
		open (my $file_cfg_local, '>:encoding(utf-8)', "$tmp_dir/${date_time_file}_${key_number_line_mac}-local.cfg") || die "Error opening file: ${date_time_file}_${key_number_line_mac}-local.cfg $!";
#####			print $file_cfg_local "#!version:1.0.0.1\n";
			$hash_local_cfg_print{$key_number_line_mac}{'#!version:1.0.0.1'} = 1;
			if ((defined $hash_mac_model{${key_number_line_mac}}) && (($hash_mac_model{${key_number_line_mac}} eq 'w52') || ($hash_mac_model{${key_number_line_mac}} eq 'w56') || ($hash_mac_model{${key_number_line_mac}} eq 'w60'))){
				foreach my $key_number_line_number(sort { $hash_number_line{$key_number_line_mac}{$a} <=> $hash_number_line{$key_number_line_mac}{$b} } keys %{$hash_number_line{$key_number_line_mac}}){
					my $temp_date = "handset."."$hash_number_line{$key_number_line_mac}{$key_number_line_number}".".name";
					if (exists($hash_local_cfg_mac{$key_number_line_mac}{$temp_date})){
						
					}else{
						my $local_print = "$temp_date"." = "."$key_number_line_number";
#####						print $file_cfg_local "$local_print\n";
						$hash_local_cfg_mac{$key_number_line_mac}{$temp_date} = $key_number_line_number;
						$hash_local_cfg_print{$key_number_line_mac}{$local_print} = 1;
					}
				}
			}
			my $yes_file_cfg_local = `ls -la $dir_tftp| grep ${key_number_line_mac}-local.cfg\$`;
###			my $date_time_file_now = strftime "%Y-%m-%d %H:%M:%S", localtime(time);
			$date_time_file_now = strftime "%Y-%m-%d %H:%M:%S", localtime(time);
			if ($yes_file_cfg_local eq ''){
				open(my $file_dir_log, '>>:encoding(utf-8)', "$dir_log/stat.log") || die "Error opening file: $dir_log/stat.log $!";
					print $file_dir_log "$date_time_file_now\t${key_number_line_mac}-local.cfg\t Файла нет\n";
				close($file_dir_log);
				sleep 30;
				$yes_file_cfg_local = `ls -la $dir_tftp| grep ${key_number_line_mac}-local.cfg\$`;
			}
			my $mtime = 0;
			my $size_file = 0;
			my $s = 0;
			my $time_now = time;
			if ($yes_file_cfg_local ne ''){
				$mtime = (stat("$dir_tftp/${key_number_line_mac}-local.cfg"))[9];
				$size_file = (-s "$dir_tftp/${key_number_line_mac}-local.cfg");
				$difference_in_time = ($time_now - $mtime);
				while($size_file < 17){
					if($s==10){
						open(my $file_dir_log, '>>:encoding(utf-8)', "$dir_log/stat.log") || die "Error opening file: $dir_log/stat.log $!";
							print $file_dir_log "$date_time_file_now\t${key_number_line_mac}-local.cfg\t$difference_in_time\tРазмер файла: $size_file\n";
						close($file_dir_log);
						last;
					}
					sleep 10;
					$s++;
					$size_file = (-s "$dir_tftp/${key_number_line_mac}-local.cfg");
				}
				if($s==10){
					next;
				}
				while (($difference_in_time <= 10) or (($difference_in_time >= 295) and ($difference_in_time <= 310))){
					$date_time_file_now = strftime "%Y-%m-%d %H:%M:%S", localtime(time);
#					open(my $file_dir_log, '>>:encoding(utf-8)', "$dir_log/stat.log") || die "Error opening file: $dir_log/stat.log $!";
#						print $file_dir_log "$date_time_file_now\t${key_number_line_mac}-local.cfg\t$difference_in_time\n";
#						print "$date_time_file_now\t${key_number_line_mac}-local.cfg\t$difference_in_time\n";
#					close($file_dir_log);
					sleep 11;
					$mtime = (stat("$dir_tftp/${key_number_line_mac}-local.cfg"))[9];
					$time_now = time;
					$difference_in_time = ($time_now - $mtime);
				}
			}
			if ($yes_file_cfg_local ne ''){
				my %hash_linekey = ();
				my $linekey_start = 0;
				my $lang_gui = 0;
				my $lang_wui = 0;
				open (my $file_cfg_local_old, '<:encoding(UTF-8)', "$dir_tftp/${key_number_line_mac}-local.cfg") || die "Error opening file: ${key_number_line_mac}-local.cfg $!";
					while (defined(my $line_cfg_local_old = <$file_cfg_local_old>)){
						chomp ($line_cfg_local_old);
						if ((exists($hash_local_cfg_print{$key_number_line_mac}{'#!version:1.0.0.1'})) && ($hash_local_cfg_print{$key_number_line_mac}{'#!version:1.0.0.1'} == 1)){
							print $file_cfg_local "\#\!version:1.0.0.1\n";
							$hash_local_cfg_print{$key_number_line_mac}{'#!version:1.0.0.1'} = 0;
						}
						if ((exists($hash_local_cfg_print{$key_number_line_mac}{$line_cfg_local_old})) && ($hash_local_cfg_print{$key_number_line_mac}{$line_cfg_local_old} == 1)){
							print $file_cfg_local "$line_cfg_local_old\n";
							$hash_local_cfg_print{$key_number_line_mac}{$line_cfg_local_old} = 0;
##							print("$key_number_line_mac $line_cfg_local_old $hash_local_cfg_print{$key_number_line_mac}{$line_cfg_local_old}\n");
						}elsif ($line_cfg_local_old =~ / = /){
							my @mas_line_cfg_local_old = split (/ = /,$line_cfg_local_old,2);
							if (exists($hash_local_cfg_mac{$key_number_line_mac}{$mas_line_cfg_local_old[0]})){
								if ((exists($hash_local_cfg_print{$key_number_line_mac}{$line_cfg_local_old})) && ($hash_local_cfg_print{$key_number_line_mac}{$line_cfg_local_old} == 1)){
									print $file_cfg_local "$line_cfg_local_old\n";
									$hash_local_cfg_print{$key_number_line_mac}{$line_cfg_local_old} = 0;
								}
							}elsif($mas_line_cfg_local_old[0] eq 'static.network.vpn_enable'){
								if ($linekey_start == 1){
									print "!!!!!$file_cfg_local!!!!!!\n";
									&print_array_linekey($file_cfg_local,\%hash_linekey);
									$linekey_start = 0;
								}
								next;
							}elsif($mas_line_cfg_local_old[0] =~ /^account.\d{1,2}.always_fwd.enable$/){
								print $file_cfg_local "$mas_line_cfg_local_old[0] = 0\n";
							}elsif($mas_line_cfg_local_old[0] =~ /^account.\d{1,2}.always_fwd.target$/){
								print $file_cfg_local "$mas_line_cfg_local_old[0] = \%EMPTY\%\n";
							}elsif($mas_line_cfg_local_old[0] =~ /^linekey.\d{1,2}./){
								$linekey_start = 1;
								my @number_linekey = split (/\./,$mas_line_cfg_local_old[0],-1);
								$hash_linekey{"${number_linekey[0]}.${number_linekey[1]}"}{${number_linekey[2]}} = $mas_line_cfg_local_old[1];
#								print "$number_linekey[0].$number_linekey[1]\t$number_linekey[2] = $mas_line_cfg_local_old[1]\n";
##								print $file_cfg_local "$line_cfg_local_old\n";
							}else{
								if ($linekey_start == 1){
									&print_array_linekey($file_cfg_local,\%hash_linekey);
									$linekey_start = 0;
								}
								print $file_cfg_local "$line_cfg_local_old\n";
								$hash_local_cfg_print{$key_number_line_mac}{$line_cfg_local_old} = 0;
							}
						}else{
							if ($linekey_start == 1){
								&print_array_linekey($file_cfg_local,\%hash_linekey);
								$linekey_start = 0;
							}
							if (exists($hash_local_cfg_print{$key_number_line_mac}{$line_cfg_local_old})){
								if ($hash_local_cfg_print{$key_number_line_mac}{$line_cfg_local_old} != 0){
									print $file_cfg_local "$line_cfg_local_old\n";
									$hash_local_cfg_print{$key_number_line_mac}{$line_cfg_local_old} = 0;
								}
							}else{
								print $file_cfg_local "$line_cfg_local_old\n";
								$hash_local_cfg_print{$key_number_line_mac}{$line_cfg_local_old} = 0;
							}
						}
					}
					foreach my $key_date (sort keys %{$hash_local_cfg_print{$key_number_line_mac}}){
						if ($hash_local_cfg_print{$key_number_line_mac}{$key_date} == 1){
							print $file_cfg_local "$key_date\n";
							$hash_local_cfg_print{$key_number_line_mac}{$key_date} = 0;
						}
					}
					if ($linekey_start == 1){
						&print_array_linekey($file_cfg_local,\%hash_linekey);
						$linekey_start = 0;
					}
				close ($file_cfg_local_old);
			}
		close ($file_cfg_local);

		my $yes_file_cfg = `ls -la $dir_tftp| grep ${key_number_line_mac}.cfg\$`;
		if ($yes_file_cfg eq ''){
			open (my $file_cfg_mac, '>:encoding(UTF-8)', "$dir_tftp/${key_number_line_mac}.cfg") || die "Error opening file: ${key_number_line_mac}.cfg $!";
			close ($file_cfg_mac);
			`chown tftpd:tftpd $dir_tftp/${key_number_line_mac}.cfg`;
			`chmod 664 $dir_tftp/${key_number_line_mac}.cfg`;
			print "!!!!!!!!$dir_tftp/${key_number_line_mac}.cfg\n";
		}
		&diff_file("$dir_tftp", "$tmp_dir", "${key_number_line_mac}.cfg");
		$yes_file_cfg_local = `ls -la $dir_tftp| grep ${key_number_line_mac}-local.cfg\$`;
		if ($yes_file_cfg_local eq ''){
			open (my $file_cfg_local_mac, '>:encoding(UTF-8)', "$dir_tftp/${key_number_line_mac}-local.cfg") || die "Error opening file: ${key_number_line_mac}-local.cfg $!";
			close ($file_cfg_local_mac);
			open (my $file_cfg_local, '>:encoding(utf-8)', "$tmp_dir/${date_time_file}_${key_number_line_mac}-local.cfg") || die "Error opening file: ${date_time_file}_${key_number_line_mac}-local.cfg $!";
				if ((exists($hash_local_cfg_print{$key_number_line_mac}{'#!version:1.0.0.1'})) && ($hash_local_cfg_print{$key_number_line_mac}{'#!version:1.0.0.1'} == 1)){
					print $file_cfg_local "\#\!version:1.0.0.1\n";
					$hash_local_cfg_print{$key_number_line_mac}{'#!version:1.0.0.1'} = 0;
				}
				foreach my $key_date (sort keys %{$hash_local_cfg_print{$key_number_line_mac}}){
					if ($hash_local_cfg_print{$key_number_line_mac}{$key_date} == 1){
						print $file_cfg_local "$key_date\n";
						$hash_local_cfg_print{$key_number_line_mac}{$key_date} = 0;
					}
				}
			close ($file_cfg_local);
			`chown tftpd:tftpd $dir_tftp/${key_number_line_mac}-local.cfg`;
			`chmod 664 $dir_tftp/${key_number_line_mac}-local.cfg`;
			print "Был создан файл: $dir_tftp/${key_number_line_mac}-local.cfg\n";
		}
		&diff_file("$dir_tftp", "$tmp_dir", "${key_number_line_mac}-local.cfg");
	}elsif(exists($hash_brand_model_conf{"$brand_cisco"}{$hash_mac_model{$key_number_line_mac}})){
		my $mac_name_file_cisco = uc($key_number_line_mac);
	
#		$hash_brand_model_conf{$brand}{$hash_mac_model{$key_number_line_mac}}{'name_cfg'} = "${$hash_mac_model{$key_number_line_mac}}.cfg";
#		open (my $name_cfg, '<:encoding(UTF-8)', "$dir_devices/$brand/$hash_mac_model{$key_number_line_mac}/$hash_mac_model{$key_number_line_mac}.cfg") || die "Error opening file: $dir_devices/$brand/$line_file_brand_model/$hash_mac_model{$key_number_line_mac}.cfg $!";
	
		# !!!Cisco телефоны до перезагрузки не скачивают файл конфигурации. Рассмотреть вариант создания функции, которая будет по ssh ребутать cisco ip phone.
		my $simple = XML::Simple->new(ForceArray => 1, KeepRoot => 1);
		$XML::Simple::PREFERRED_PARSER = "XML::Parser";
		my $data = $simple->XMLin("$dir_devices/$brand_cisco/$hash_mac_model{$key_number_line_mac}/SEPmac.cnf.xml");
#		print Dumper($data) . "\n";
		open (my $file_model_cfg, '<:encoding(UTF-8)', "$dir_devices/$brand_cisco/$hash_mac_model{$key_number_line_mac}/$hash_mac_model{$key_number_line_mac}.cfg") || die "Error opening file: $hash_mac_model{$key_number_line_mac}.cfg $!";
			my %types = ();
			while (defined(my $line_cfg = <$file_model_cfg>)){
				if ($line_cfg =~ /^(\#|\;|$)/){
					next;
				}
				chomp($line_cfg);
				my @mas_line_cfg = split (/ = /,$line_cfg,2);
				my @mas_line_cfg_name = split (/\;/,$mas_line_cfg[0],-1);
				my $length_array = @mas_line_cfg_name;
				if($length_array == 1){
					@{$data->{device}}[0] -> {$mas_line_cfg_name[0]}[0] = "$mas_line_cfg[1]";
				}elsif($length_array == 2){
					@{$data->{device}}[0] -> {$mas_line_cfg_name[0]}[0] -> {$mas_line_cfg_name[1]}[0] = "$mas_line_cfg[1]";
				}elsif($length_array == 3){
					@{$data->{device}}[0] -> {$mas_line_cfg_name[0]}[0] -> {$mas_line_cfg_name[1]}[0] -> {$mas_line_cfg_name[2]}[0] = "$mas_line_cfg[1]";
				}elsif($length_array == 4){
					@{$data->{device}}[0] -> {$mas_line_cfg_name[0]}[0] -> {$mas_line_cfg_name[1]}[0] -> {$mas_line_cfg_name[2]}[0] -> {$mas_line_cfg_name[3]}[0] = "$mas_line_cfg[1]";
				}elsif($length_array == 5){
					@{$data->{device}}[0] -> {$mas_line_cfg_name[0]}[0] -> {$mas_line_cfg_name[1]}[0] -> {$mas_line_cfg_name[2]}[0] -> {$mas_line_cfg_name[3]}[0] -> {$mas_line_cfg_name[4]}[0] = "$mas_line_cfg[1]";
				}elsif($length_array == 6){
					@{$data->{device}}[0] -> {$mas_line_cfg_name[0]}[0] -> {$mas_line_cfg_name[1]}[0] -> {$mas_line_cfg_name[2]}[0] -> {$mas_line_cfg_name[3]}[0] -> {$mas_line_cfg_name[4]}[0] -> {$mas_line_cfg_name[5]}[0] = "$mas_line_cfg[1]";
				}elsif($length_array == 7){
					@{$data->{device}}[0] -> {$mas_line_cfg_name[0]}[0] -> {$mas_line_cfg_name[1]}[0] -> {$mas_line_cfg_name[2]}[0] -> {$mas_line_cfg_name[3]}[0] -> {$mas_line_cfg_name[4]}[0] -> {$mas_line_cfg_name[5]}[0] -> {$mas_line_cfg_name[6]}[0] = "$mas_line_cfg[1]";
				}elsif($length_array == 8){
					@{$data->{device}}[0] -> {$mas_line_cfg_name[0]}[0] -> {$mas_line_cfg_name[1]}[0] -> {$mas_line_cfg_name[2]}[0] -> {$mas_line_cfg_name[3]}[0] -> {$mas_line_cfg_name[4]}[0] -> {$mas_line_cfg_name[5]}[0] -> {$mas_line_cfg_name[6]}[0] -> {$mas_line_cfg_name[7]}[0] = "$mas_line_cfg[1]";
				}elsif($length_array == 9){
					@{$data->{device}}[0] -> {$mas_line_cfg_name[0]}[0] -> {$mas_line_cfg_name[1]}[0] -> {$mas_line_cfg_name[2]}[0] -> {$mas_line_cfg_name[3]}[0] -> {$mas_line_cfg_name[4]}[0] -> {$mas_line_cfg_name[5]}[0] -> {$mas_line_cfg_name[6]}[0] -> {$mas_line_cfg_name[7]}[0] -> {$mas_line_cfg_name[8]}[0] = "$mas_line_cfg[1]";
				}elsif($length_array == 10){
					@{$data->{device}}[0] -> {$mas_line_cfg_name[0]}[0] -> {$mas_line_cfg_name[1]}[0] -> {$mas_line_cfg_name[2]}[0] -> {$mas_line_cfg_name[3]}[0] -> {$mas_line_cfg_name[4]}[0] -> {$mas_line_cfg_name[5]}[0] -> {$mas_line_cfg_name[6]}[0] -> {$mas_line_cfg_name[7]}[0] -> {$mas_line_cfg_name[8]}[0] -> {$mas_line_cfg_name[9]}[0] = "$mas_line_cfg[1]";
				}else{
					print "Error_10 @mas_line_cfg_name\n";
				}
			}
		close ($file_model_cfg);

#!#		@{$data->{device}}[0]->{sipProfile}[0]->{phoneLabel}[0] = 'No Name';
		
#!#		my @array = @{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line};
#!#		my $size = @array;
#!#		for(my $i = 0;$i <= $size; $i++){
#!#			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{featureLabel}[0] = '00000';
#!#			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{proxy}[0] = '0.0.0.0';
#!#			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{name}[0] = '00000';
#!#			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{displayName}[0] = '00000';
#!#			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{contact}[0] = '00000';
#!#			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{authName}[0] = '00000';
#!#			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{authPassword}[0] = '00000';
#!#		}
		$simple->XMLout($data, 
				KeepRoot   => 1, 
#				NoSort     => 1, 
				OutputFile => "$tmp_dir/${date_time_file}".'_SEP'."${mac_name_file_cisco}".'.cnf.xml',
				XMLDecl    => '<?xml version="1.0" encoding="UTF-8"?>',
				);
		
		my $yes_file_cfg = `ls -la $dir_tftp| grep SEP${mac_name_file_cisco}.cnf.xml\$`;
		if ($yes_file_cfg eq ''){
			open (my $file_cfg_mac, '>:encoding(UTF-8)', "$dir_tftp/SEP${mac_name_file_cisco}.cnf.xml") || die "Error opening file: $dir_tftp/${mac_name_file_cisco}.cnf.xml $!";
			close ($file_cfg_mac);
			`chown tftpd:tftpd $dir_tftp/SEP${mac_name_file_cisco}.cnf.xml`;
			`chmod 664 $dir_tftp/SEP${mac_name_file_cisco}.cnf.xml`;
			print "!!!!!!!!$dir_tftp/SEP${mac_name_file_cisco}.cnf.xml\n";
		}
		&diff_file("$dir_tftp", "$tmp_dir", "SEP${mac_name_file_cisco}.cnf.xml");
	}
}
close ($file_1);

#Фиксируем изменения. (был добавлен или удален номер телефона или устройство в AD)
&diff_file("$dir_conf", "$tmp_dir", 'ad_sip-phone.txt');
#Фиксируем изменения. (был добавлен или удален номер телефона)
&diff_file("$dir_conf", "$tmp_dir", 'conf_number_line.conf');

#отвечает за перезагрузку диалплата Asterisk и его модулей. Эта команда соответствует нажатию кнопки "Apply Changes" через GUI FreePBX.
##if ($reload_yes == 1){
##	`sudo -u root /usr/sbin/fwconsole reload`;
##}


#----------------------------------------------------
#linekey.1.line = 1
#linekey.1.value = %EMPTY%
#linekey.1.type = 15
#linekey.1.label = %EMPTY%
#linekey.1.extension = %EMPTY%
#linekey.1.xml_phonebook = 0
#linekey.1.pickup_value = %EMPTY%

sub print_array_linekey{
	my $file_cfg_local = shift;
	my ($hash_linekey) = @_;
	foreach my $key_line_linekey (sort keys %$hash_linekey){
		if ((exists($$hash_linekey{$key_line_linekey}{value})) && (exists($hash_sipid_displayname{$$hash_linekey{$key_line_linekey}{value}})) && ($$hash_linekey{$key_line_linekey}{label} ne $hash_sipid_displayname{$$hash_linekey{$key_line_linekey}{value}})){
##			print "!!$$hash_linekey{$key_line_linekey}{value}\t$hash_sipid_displayname{$$hash_linekey{$key_line_linekey}{value}}!!\n";
			print "Замена $$hash_linekey{$key_line_linekey}{label} на $hash_sipid_displayname{$$hash_linekey{$key_line_linekey}{value}}\n"; 
			$$hash_linekey{$key_line_linekey}{label} = $hash_sipid_displayname{$$hash_linekey{$key_line_linekey}{value}};
		}
		my $i = 7;
		my @label_value = ();
		foreach my $linekey_type (sort keys %{$$hash_linekey{$key_line_linekey}}){
##			print "$key_line_linekey.$linekey_type = $$hash_linekey{$key_line_linekey}{$linekey_type}\n";
			if ($linekey_type eq 'extension'){
				$label_value[0] = "$key_line_linekey.$linekey_type = $$hash_linekey{$key_line_linekey}{$linekey_type}";
			}elsif($linekey_type eq 'label'){
				$label_value[1] = "$key_line_linekey.$linekey_type = $$hash_linekey{$key_line_linekey}{$linekey_type}";
			}elsif($linekey_type eq 'line'){
				$label_value[2] = "$key_line_linekey.$linekey_type = $$hash_linekey{$key_line_linekey}{$linekey_type}";
			}elsif($linekey_type eq 'pickup_value'){
				$label_value[3] = "$key_line_linekey.$linekey_type = $$hash_linekey{$key_line_linekey}{$linekey_type}";
			}elsif($linekey_type eq 'type'){
				$label_value[4] = "$key_line_linekey.$linekey_type = $$hash_linekey{$key_line_linekey}{$linekey_type}";
			}elsif($linekey_type eq 'value'){
				$label_value[5] = "$key_line_linekey.$linekey_type = $$hash_linekey{$key_line_linekey}{$linekey_type}";
			}elsif($linekey_type eq 'xml_phonebook'){
				$label_value[6] = "$key_line_linekey.$linekey_type = $$hash_linekey{$key_line_linekey}{$linekey_type}";
			}else{
				$label_value[$i] = "$key_line_linekey.$linekey_type = $$hash_linekey{$key_line_linekey}{$linekey_type}";
#				print $file_cfg_local "$key_line_linekey.$linekey_type = $$hash_linekey{$key_line_linekey}{$linekey_type}\n";
				$i++;
			}
		}
		foreach my $line_new (@label_value){
			if (defined $line_new){
				print $file_cfg_local "$line_new\n";
			}
		}
	}
	%$hash_linekey = ();
}

#Функция создания файла .boot для телефонов Yealink
sub conf_boot{
	my $brand = shift;
	my $mac_address = shift;
	my $model = shift;
	if (exists($hash_brand_model_conf{$brand}{$model})){
		open (my $file_boot, '>:encoding(UTF-8)', "$tmp_dir/${date_time_file}_${mac_address}.boot") || die "Error opening file: ${date_time_file}_${mac_address}.boot $!";
			print $file_boot '#!version:1.0.0.1';
			print $file_boot "\n## the header above must appear as-is in the first line\n";
			print $file_boot "     \n";
			print $file_boot "include:config \"$hash_brand_model_conf{$brand}{$model}{'mac_boot'}\"\n";
			print $file_boot "include:config \"${mac_address}.cfg\"\n";
			print $file_boot "     \n";
			print $file_boot "overwrite_mode = 1\n";
		close ($file_boot);

		my $yes_file_boot = `ls -la $dir_tftp| grep ${mac_address}.boot\$`;
		if ($yes_file_boot eq ''){
			open (my $file, '>:encoding(UTF-8)', "$dir_tftp/${mac_address}.boot") || die "Error opening file: $dir_tftp/${mac_address}.boot $!";
			close ($file);
		}
		&diff_file("$dir_tftp", "$tmp_dir", "${mac_address}.boot");
	}else{
		print "ERROR_1: $mac_address\t$model\n";
	}
}

sub add_line{
		my $mac_address = shift;
		my $number = shift;
		my $constanta_number = 0;
		my %hash_static_line = (
					'1' => '0',
					'2' => '0',
					'3' => '0',
					'4' => '0',
					'5' => '0',
					'6' => '0',
					'7' => '0',
					'8' => '0',
					'9' => '0',
					'10' => '0',
					'11' => '0',
					'12' => '0',
					'13' => '0',
					'14' => '0',
					'15' => '0',
					'16' => '0',
					'17' => '0',
					'18' => '0',
					'19' => '0',
					'20' => '0',
					'21' => '0',
					'22' => '0',
					'23' => '0',
					'24' => '0',
					'25' => '0',
					'26' => '0',
					);
		if (exists($hash_number_line{$mac_address})){
			foreach my $key_number_line_number(sort keys %{$hash_number_line{$mac_address}}){
				delete $hash_static_line{$hash_number_line{$mac_address}{$key_number_line_number}};
				if ("$number" eq "$key_number_line_number"){
					$constanta_number = 1;
				}
			}
			if ($constanta_number == 0){
				foreach my $key_number_line_static (sort {$a<=>$b} keys %hash_static_line){
					$hash_number_line{$mac_address}{$number} = $key_number_line_static;
					last;
				}
			}
		}else{
			$hash_number_line{$mac_address}{$number} = 1;
		}
}
#cisco 7911G
#<name>**IP-ADDRESS-SIP-SERV**</name>
#<sipPort>**PORT-SIP-SERV**</sipPort>
#<processNodeName>**IP-ADDRESS-SIP-SERV**</processNodeName>
#<featureLabel>**LINE-DISPLAY-NAME**</featureLabel>
#<proxy>**IP-ADDRESS-PROXY**</proxy>
#<port>**PORT-PROXY**</port>
#<name>**NAME**</name>
#<displayName>**DISPLAY-NAME**</displayName>
#<contact>**CONTACT**</contact>
#<authName>**AUTH-NAME**</authName>
#<authPassword>**AUTH-PASSWORD**</authPassword>
#Функция удаления sip-учеток номеров из файлов конфигурации, которые были удалены в AD.
sub number_zero{
	my $brand = shift;
	my $file = shift;
	if($brand eq 'yealink'){
		open (my $file_tmp, '>:encoding(UTF-8)', "$tmp_dir/${date_time_file}_${file}") || die "Error opening file: ${date_time_file}_${file} $!";
			open (my $file_1, '<:encoding(UTF-8)', "$dir_tftp/${file}") || die "Error opening file: ${file} $!";
				while (defined(my $line_cfg_file_old = <$file_1>)){
					chomp ($line_cfg_file_old);
					if ($line_cfg_file_old =~ / = /){
						my @mas_line_cfg_file_old = split (/ = /,$line_cfg_file_old,-1);
						if ($mas_line_cfg_file_old[0] =~ /^(account\.\d+\.enable|account\.\d+\.sip_server\.\d+\.register_on_enable)$/){
							print $file_tmp "$mas_line_cfg_file_old[0] = 0\n";
						}elsif ($mas_line_cfg_file_old[0] =~ /^(account\.\d+\.label|account\.\d+\.display_name|account\.\d+\.auth_name|account\.\d+\.user_name)$/){
							print $file_tmp "$mas_line_cfg_file_old[0] = 000\n";
						}elsif ($mas_line_cfg_file_old[0] =~ /(^account\.\d+\.password)$/){
							print $file_tmp "$mas_line_cfg_file_old[0] = 000\n";
						}else{
							print $file_tmp "$line_cfg_file_old\n";
						}
					}else{
						print $file_tmp "$line_cfg_file_old\n";
					}
				}
			close ($file_1);
		close ($file_tmp);
	}elsif($brand eq 'cisco'){
# !!!Cisco телефоны до перезагрузки не скачивают файл конфигурации. Рассмотреть вариант создания функции, которая будет по ssh ребутать cisco ip phone.
		my $simple = XML::Simple->new(ForceArray => 1, KeepRoot => 1);
		$XML::Simple::PREFERRED_PARSER = "XML::Parser";
		my $data   = $simple->XMLin("$dir_tftp/$file");
#		print Dumper($data) . "\n";
		@{$data->{device}}[0]->{devicePool}[0]->{callManagerGroup}[0]->{members}[0]->{member}[0]->{callManager}[0]->{name}[0] = '0.0.0.0';
		@{$data->{device}}[0]->{devicePool}[0]->{callManagerGroup}[0]->{members}[0]->{member}[0]->{callManager}[0]->{processNodeName}[0] = '0.0.0.0';
		@{$data->{device}}[0]->{authenticationURL}[0] = '';
		@{$data->{device}}[0]->{directoryURL}[0] = '';
		@{$data->{device}}[0]->{idleURL}[0] = '';
		@{$data->{device}}[0]->{informationURL}[0] = '';
		@{$data->{device}}[0]->{messagesURL}[0] = '';
		@{$data->{device}}[0]->{proxyServerURL}[0] = '';
		@{$data->{device}}[0]->{servicesURL}[0] = '';
		@{$data->{device}}[0]->{sipProfile}[0]->{phoneLabel}[0] = 'No Name';
		
		my @array = @{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line};
		my $size = @array;
		for(my $i = 0;$i <= $size; $i++){
			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{featureLabel}[0] = '00000';
			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{proxy}[0] = '0.0.0.0';
			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{name}[0] = '00000';
			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{displayName}[0] = '00000';
			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{contact}[0] = '00000';
			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{authName}[0] = '00000';
			@{$data->{device}}[0]->{sipProfile}[0]->{sipLines}[0]->{line}[$i]->{authPassword}[0] = '00000';
		}
		$simple->XMLout($data, 
				KeepRoot   => 1, 
#				NoSort     => 1, 
				OutputFile => "$tmp_dir/${date_time_file}_${file}",
				XMLDecl    => '<?xml version="1.0" encoding="UTF-8"?>',
				);
	}
}

#Функция обновления файлов конфигураций и фиксации изменений в history.
sub diff_file{
	my $dir_file = shift;
	my $tmp_dir_file = shift;
	my $original_file = shift;
	
	my $diff_file = `diff -u $dir_file/$original_file $tmp_dir_file/${date_time_file}_${original_file}`;
	if ($diff_file ne ''){
		my $mtime = (stat("$dir_file/$original_file"))[9];
		my $time_now = time;
		my $difference_in_time = ($time_now - $mtime);
		open(my $file_dir_lo, '>>:encoding(utf-8)', "$dir_log/stat.log") || die "Error opening file: $dir_log/stat.log $!";
			print $file_dir_lo "$date_time_file_now\t$original_file\t$difference_in_time\n";
		close($file_dir_lo);
		$reload_yes = 1;
		`diff -u $dir_file/${original_file} $tmp_dir_file/${date_time_file}_${original_file} > $dir_history/$date_directory/${date_time_file}_${original_file}.diff`;
		`cat $dir_file/${original_file} > $dir_history/$date_directory/${date_time_file}_${original_file}`;
		`cat $tmp_dir_file/${date_time_file}_${original_file} > $dir_file/$original_file && chown tftpd:tftpd $dir_file/$original_file`;
	}
	`rm $tmp_dir_file/${date_time_file}_${original_file}`;
}
