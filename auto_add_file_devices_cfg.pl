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