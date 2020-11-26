#!/usr/bin/perl -w
# Скрипт написал Крук Иван Александрович <kruk.ivan@itmh.ru>
# Скрипт автоматически создает пустые файлы конфигурации для новых моделей телефонов

use 5.010;
use strict;
use warnings;
use POSIX qw(strftime);
use locale;
use DBI;
use Time::Local;
use encoding 'utf-8';
#use Date::Dumper qw(Dumper);
#fwconsole userman --syncall --force

my $dir_conf = '/opt/asterisk/script_new/autoprovisioning';			#Директория для файлов конфигурации сервиса autoprovisioning.
my $dir_devices = '/opt/asterisk/script_new/devices';				#Директория шаблонов конфигурации всех поддерживаемых моделей sip-телефонов 
my %hash_model_conf = (
			't18'		=> 'y000000000009.cfg',
			't19'	=> 'y000000000053.cfg',
#			't19' 		=> 'y000000000031.cfg',
			't19_e2' 	=> 'y000000000053.cfg',
			't20'		=> 'y000000000007.cfg',
			't21'		=> 'y000000000034.cfg',
			't21p_e2'	=> 'y000000000052.cfg',
			't21pe2'	=> 'y000000000052.cfg',
			't21e2'		=> 'y000000000052.cfg',
			't21p'		=> 'y000000000052.cfg',
			't21_e2'	=> 'y000000000052.cfg',
			't22'		=> 'y000000000005.cfg',
			't23'		=> 'y000000000044.cfg',
			't23p'		=> 'y000000000044.cfg',
			't23g'		=> 'y000000000044.cfg',
			't26'		=> 'y000000000004.cfg',
			't26p'		=> 'y000000000004.cfg',
			't27'	=> 'y000000000045.cfg',
			't27p'		=> 'y000000000045.cfg',
			't27g'		=> 'y000000000069.cfg',
			't29'	=> 'y000000000046.cfg',
			't29g'		=> 'y000000000046.cfg',
			't32'		=> 'y000000000032.cfg',
			't38'		=> 'y000000000038.cfg',
			't40'	=> 'y000000000054.cfg',
			't40p'		=> 'y000000000054.cfg',
			't40g'		=> 'y000000000076.cfg',
			't41'	=> 'y000000000036.cfg',
			't41p'		=> 'y000000000036.cfg',
			't41s'		=> 'y000000000068.cfg',
			't42'	=> 'y000000000029.cfg',
			't42g'		=> 'y000000000029.cfg',
			't42s'		=> 'y000000000067.cfg',
			't42u'		=> 'y000000000116.cfg',
			't43u'		=> 'y000000000107.cfg',
			't46'	=> 'y000000000066.cfg',
			't46g'		=> 'y000000000028.cfg',
			't46s'		=> 'y000000000066.cfg',
			't46u'		=> 'y000000000108.cfg',
			't48'	=> 'y000000000035.cfg',
			't48g'		=> 'y000000000035.cfg',
			't48s'		=> 'y000000000065.cfg',
			't48u'		=> 'y000000000109.cfg',
			't52s'		=> 'y000000000074.cfg',
			't54s'		=> 'y000000000070.cfg',
			't53'		=> 'y000000000095.cfg',
			't54w'		=> 'y000000000096.cfg',
			'vp-t49'	=> 'y000000000051.cfg',
			't49g'		=> 'y000000000051.cfg',
			't57w'		=> 'y000000000097.cfg',
			't58'		=> 'y000000000058.cfg',
			'vp-t59'	=> 'y000000000091.cfg',
			'w52'		=> 'y000000000025.cfg',
			'w53'		=> 'y000000000077.cfg',
			'w56'		=> 'y000000000025.cfg',
			'w60'		=> 'y000000000077.cfg',
			'vp530'		=> 'y000000000023.cfg',
			'cp860'		=> 'y000000000037.cfg',
			'cp920'		=> 'y000000000078.cfg',
			'cp930w'	=> 'y000000000077.cfg',
			'cp960'		=> 'y000000000073.cfg',
			't30'		=> 'y000000000127.cfg',
			't30p'		=> 'y000000000127.cfg',
			't31'		=> 'y000000000123.cfg',
			't31g'		=> 'y000000000123.cfg',
			't31p'		=> 'y000000000123.cfg',
			't33g'		=> 'y000000000124.cfg',
			't33p'		=> 'y000000000124.cfg',
			);
open (my $file_devices, '<:encoding(UTF-8)', "$dir_conf/devices.txt") || die "Error opening file: $dir_conf/devices.txt $!";
	while (defined(my $line_devices = <$file_devices>)){
		if ($line_devices =~ /^(\#|\;|$)/){
			print "$line_devices\n";
			next;
		}
		chomp ($line_devices);
		my @array_line_devices = split (/\t/,$line_devices,-1);
		if (defined $array_line_devices[0]){
			my $yes_dir_devices = `ls -la $dir_devices| grep $array_line_devices[0]\$`;
			if ($yes_dir_devices eq ''){
				mkdir "/opt/asterisk/script_new/devices/$array_line_devices[0]", 0755 or warn "Cannot make fred directory: $array_line_devices[0]\n$!";
			}
			my $yes_dir_devices_brend = `ls -la $dir_devices/$array_line_devices[0]| grep $array_line_devices[1]\$`;
			if ($yes_dir_devices_brend eq ''){
				mkdir "/opt/asterisk/script_new/devices/$array_line_devices[0]/$array_line_devices[1]", 0755 or warn "Cannot make fred directory: $array_line_devices[1]\n$!";
				open(my $file_devices_autoprovisioning, '>>:encoding(utf-8)', "$dir_devices/$array_line_devices[0]/$array_line_devices[1]/$array_line_devices[1].cfg") || die "Error opening file: $dir_devices/$array_line_devices[0]/$array_line_devices[1]/$array_line_devices[1].cfg $!";
				if (exists ($hash_model_conf{$array_line_devices[1]})){
					print $file_devices_autoprovisioning 'mac_boot = ' . "$hash_model_conf{$array_line_devices[1]}\n";
				}else{
					print ("$array_line_devices[1]\n");
				}
				close($file_devices_autoprovisioning);
			}
		}
	}
close ($file_devices);


#			my $yes_file_cfg_local = `ls -la $dir| grep ${key_number_line_mac}-local.cfg\$`;
#			$date_time_file_now = strftime "%Y-%m-%d %H:%M:%S", localtime(time);
#			if ($yes_file_cfg_local eq ''){
#				open(my $file_dir_log, '>>:encoding(utf-8)', "$dir_log/stat.log") || die "Error opening file: $dir_log/stat.log $!";
#					print $file_dir_log "$date_time_file_now\t${key_number_line_mac}-local.cfg\t Файла нет\n";
#				close($file_dir_log);
#				sleep 30;
#				$yes_file_cfg_local = `ls -la $dir| grep ${key_number_line_mac}-local.cfg\$`;
#			}